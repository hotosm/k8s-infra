# Migrating a pgstac catalog

Export as NDJSON, let `pypgstac` own the schema. `pg_dump`/`pg_restore` do not
work on pgstac: generated columns inline functions the dump emits later in the
file, and `-t pgstac.items` matches only the partitioned parent.

## 1. Targets

```fish
set SRCPOD (kubectl get pod -n eoapi -l postgres-operator.crunchydata.com/role=master \
  -o jsonpath='{.items[0].metadata.name}')
set SRCHOST (kubectl get secret -n eoapi eoapi-pguser-eoapi -o jsonpath='{.data.host}' | base64 -d)
set SRCUSER (kubectl get secret -n eoapi eoapi-pguser-eoapi -o jsonpath='{.data.user}' | base64 -d)
set SRCDB (kubectl get secret -n eoapi eoapi-pguser-eoapi -o jsonpath='{.data.dbname}' | base64 -d)
set SRCPW (kubectl get secret -n eoapi eoapi-pguser-eoapi -o jsonpath='{.data.password}' | base64 -d)

set DSTPOD oam-eoapi-pgstac-prod-db-1
set DSTDB oam-eoapi-pgstac-prod
set DSTUSER oam_stac
set DSTPW (kubectl get secret -n postgres oam-eoapi-pgstac-prod-db-creds \
  -o jsonpath='{.data.password}' | base64 -d)
```

## 2. Loader pod

```fish
# leftover rows fail the load on a duplicate key - run before every attempt
kubectl exec -n postgres $DSTPOD -- psql -d $DSTDB -c "drop schema if exists pgstac cascade"

# pin pypgstac to the version the eoapi chart ships - migrations are
# forward-only, so a DB ahead of the chart breaks its pgstacMigrate job:
#   helm template eoapi eoapi/eoapi --version <ver> -f <values> \
#     | grep -B20 'pypgstac migrate' | grep 'image:'
kubectl run pypgstac -n postgres --restart=Never --image=python:3.12-slim \
  --env=PGHOST=oam-eoapi-pgstac-prod-db-rw --env=PGDATABASE=$DSTDB \
  --env=PGUSER=$DSTUSER --env=PGPASSWORD=$DSTPW \
  --command -- sleep infinity

kubectl exec -n postgres pypgstac -- sh -c \
  'apt-get update -qq && apt-get install -y -qq --no-install-recommends postgresql-client'
kubectl exec -n postgres pypgstac -- pip install -q "pypgstac[psycopg]==0.9.10"
```

`read_json` collapses `\\` to `\` twice per line, so any item containing a
backslash fails to parse or silently loads wrong (`\\n` becomes a newline).
Expect `patched: True`; re-apply after any pod recreation.

```fish
kubectl exec -n postgres pypgstac -- python3 -c '
import re, pathlib
p = pathlib.Path("/usr/local/lib/python3.12/site-packages/pypgstac/load.py")
s = p.read_text()
s2 = re.sub(r"lineout = line\.strip\(\).*", "lineout = line.strip()", s)
print("patched:", s != s2)
p.write_text(s2)
'
```

## 3. Schema

```fish
kubectl exec -n postgres pypgstac -- pypgstac migrate
kubectl exec -n postgres $DSTPOD -- psql -c \
  "alter database \"$DSTDB\" set search_path to pgstac, public"
```

## 4. Export

```fish
# -tAc + plain select, not `copy .. to stdout` - COPY escapes backslashes.
# items.content is stored slimmed, so content_hydrate is required.
kubectl exec -n postgres pypgstac -- sh -c \
  "PGPASSWORD='$SRCPW' PGCLIENTENCODING=UTF8 psql -h $SRCHOST -U $SRCUSER -d $SRCDB -tAc \
   'select content from pgstac.collections' > /tmp/collections.ndjson"

time kubectl exec -n postgres pypgstac -- sh -c \
  "PGPASSWORD='$SRCPW' PGCLIENTENCODING=UTF8 psql -h $SRCHOST -U $SRCUSER -d $SRCDB -tAc \
   'select pgstac.content_hydrate(i) from pgstac.items i' > /tmp/items.ndjson"

# validate with orjson, not stdlib json - stdlib passes files the loader rejects
kubectl exec -n postgres pypgstac -- python3 -c "
import orjson
for path in ['/tmp/collections.ndjson', '/tmp/items.ndjson']:
    bad = 0
    for n, line in enumerate(open(path, 'rb'), 1):
        try:
            orjson.loads(line)
        except Exception as e:
            bad += 1
            if bad == 1:
                print(path, 'first bad line', n, e)
    print(path, 'bad lines:', bad)
"
```

## 5. Load

```fish
# collections first - inserting one creates its items partition.
# upsert so a re-run after a partial failure converges.
kubectl exec -n postgres pypgstac -- \
  pypgstac load collections /tmp/collections.ndjson --method upsert
time kubectl exec -n postgres pypgstac -- \
  pypgstac load items /tmp/items.ndjson --method upsert

# no matviews on 0.9.10; loop stays correct on newer pgstac
kubectl exec -n postgres $DSTPOD -- psql -d $DSTDB -c 'do $do$ declare r record; begin
  for r in select matviewname from pg_matviews where schemaname = \'pgstac\' loop
    execute format(\'refresh materialized view pgstac.%I\', r.matviewname);
  end loop;
end $do$'

kubectl exec -n postgres $DSTPOD -- psql -d $DSTDB -c "analyze"
```

## 6. Verify

```fish
echo -n "src: "; kubectl exec -n eoapi $SRCPOD -- psql -d $SRCDB -tAc \
  "select count(*) from pgstac.items"
echo -n "dst: "; kubectl exec -n postgres $DSTPOD -- psql -d $DSTDB -tAc \
  "select count(*) from pgstac.items"

kubectl exec -n postgres $DSTPOD -- psql -d $DSTDB -tAc \
  "select pgstac.search('{\"limit\": 1}')"

kubectl delete pod -n postgres pypgstac
```

> [!NOTE]
> The schema version must not be **ahead** of what the chart's `pgstacMigrate`
> job targets - migrations are forward-only and the job fails with `Could not
> determine path to get from <db> to <chart>`. Bumping the chart is not a fix:
> eoapi 0.12.2 - 0.15.0 all ship `pgstac-pypgstac:v0.10.0`, whose tag is an image
> version, not a pypgstac one - the tool inside targets schema 0.9.10.
