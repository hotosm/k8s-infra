# ScaleODM

```bash
kubectl create secret generic scaleodm-secrets \
  --from-literal=SCALEODM_DATABASE_URL="postgresql://scaleodm:xxx@scaleodm-db-rw.postgres.svc.cluster.local:5432/scaleodm" \
  --from-literal=AWS_S3_ENDPOINT="https://s3.amazonaws.com" \
  --from-literal=AWS_ACCESS_KEY_ID="xxx" \
  --from-literal=AWS_SECRET_ACCESS_KEY="xxx" \
  --from-literal=AWS_DEFAULT_REGION="us-east-1" \
  --namespace=odm \
  --dry-run=client -o yaml > secret.yaml
```

## Testing

Heartbeat (db + argo ready):

```bash
kubectl -n odm get svc scaleodm

kubectl -n odm run curl-test \
    --rm -it \
    --restart=Never \
    --image=curlimages/curl \
    --command -- curl -v http://scaleodm.odm.svc.cluster.local:31100/__heartbeat__
```

Submit a test job against the in-cluster service using imagery from
`s3://dronetm-prod/projects/005889ef-67e5-4132-935c-ce50aca81952/d00e3b91-0581-429b-916d-6d1a01008a7e/images/`.
This runs curl from a temporary pod so Kubernetes service DNS resolves. The
`options` field must be a JSON-encoded string, not a JSON array:

```bash
kubectl -n odm run scaleodm-submit \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl \
  --command -- sh -c '
    API="http://scaleodm.odm.svc.cluster.local:31100"
    PREFIX="s3://dronetm-prod/projects/005889ef-67e5-4132-935c-ce50aca81952/d00e3b91-0581-429b-916d-6d1a01008a7e"

    echo "==> Checking heartbeat at ${API}/__heartbeat__"
    curl -sv --max-time 10 "${API}/__heartbeat__" || echo "Heartbeat FAILED (exit $?)"

    echo ""
    echo "==> Submitting job to ${API}/task/new"
    PAYLOAD=$(cat <<EOF
{"name":"dronetm-prod-curl-test","readS3Path":"${PREFIX}/images/","writeS3Path":"${PREFIX}/odm/","s3Region":"us-east-1","options":"[{\"name\":\"fast-orthophoto\",\"value\":true}]"}
EOF
)
    echo "    Payload: ${PAYLOAD}"
    response=$(curl -sS --max-time 60 \
      -X POST "${API}/task/new" \
      -H "Content-Type: application/json" \
      -d "${PAYLOAD}")
    echo "    Response: ${response}"
    uuid=$(printf "%s" "${response}" | sed -n "s/.*\"uuid\":\"\([^\"]*\)\".*/\1/p")
    echo "    Task UUID: ${uuid}"
  '
```

Poll the task by replacing `<job_id>` with the value returned above:

```bash
kubectl -n odm run scaleodm-info \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl \
  --command -- curl -fsS http://scaleodm.odm.svc.cluster.local:31100/task/odm-pipeline-xxx/info
```

Inspect the task log:

```bash
kubectl -n odm run scaleodm-output \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl \
  --command -- curl -fsS "http://scaleodm.odm.svc.cluster.local:31100/task/odm-pipeline-xxx/output?line=0"
```

List tasks if you need to recover the UUID:

```bash
kubectl -n odm run scaleodm-list \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl \
  --command -- curl -fsS http://scaleodm.odm.svc.cluster.local:31100/task/list
```

After the task succeeds, ODM assets should be uploaded under the task prefix:

```bash
aws s3 ls \
  s3://dronetm-prod/projects/005889ef-67e5-4132-935c-ce50aca81952/d00e3b91-0581-429b-916d-6d1a01008a7e/ \
  --recursive
```

Verify the in-cluster port with `kubectl -n odm get svc scaleodm` — the
`Port:` field (currently `31100`) is what pods use, not `3000`.
