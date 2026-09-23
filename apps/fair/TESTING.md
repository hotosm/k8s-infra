# fAIr end-to-end test

This runbook tests the whole fAIr model workflow on production, using the API:

1. Register a base model.
2. Build a training dataset.
3. Fine-tune the model.
4. Publish the fine-tuned model.
5. Run a prediction, first through the API, then live through Knative.

The example uses `sklearn-rgb-segmentation`, a tiny model that trains in
seconds. The last section repeats the training on a GPU.

## Before you start

You need:

- `kubectl` access to the cluster, with the production context selected.
- `curl`, `jq` and the fish shell.
- A fAIr account at <https://ai.hotosm.org>.

Run every command in the same terminal, because the variables carry over
from one step to the next.

## 1. Set up

```fish
set -gx API https://api.ai.hotosm.org/api/v1
set -gx STAC https://stac.ai.hotosm.org/stac
set -gx NS fair-prod
set -gx PIPE_NS zenml-pipelines-prod
set -gx KN_NS fair-knative
set -gx DEPLOY deployment/fair-backend-backend
set -gx CRON cronjob/fair-backend-backend-knative-reconcile
set -gx MLFLOW_URL https://mlflow.ai.hotosm.org

set -gx RUN (date +%Y%m%d%H%M)
set -gx MODEL sklearn-rgb-segmentation
set -gx MODEL_DIR sklearn_rgb_segmentation
set -gx IMAGERY 'https://tiles.openaerialmap.org/62d85d11d8499800053796c1/0/62d85d11d8499800053796c2/{z}/{x}/{y}'
set -gx BBOX '[85.51678, 27.63133, 85.52323, 27.63743]'

curl -fsS $API/health/ | jq
```

Expect `postgresql`, `s3`, `stac_api` and `zenml` to be `true`.

## 2. Log in

1. Log in at <https://ai.hotosm.org>.
2. In the browser's developer tools, go to Application > Cookies and copy the
   value of the `hanko` cookie.
3. Paste it when prompted:

```fish
function fair_login --description "Paste the hanko cookie; sets TOKEN and AUTH"
    read -s -P "Paste hanko cookie: " raw; echo
    set -l jwt (string match -r "eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" -- $raw)
    if test -z "$jwt"
        echo "No complete token found, copy the whole cookie value"
        return 1
    end
    set -gx TOKEN $jwt
    set -gx AUTH "Authorization: Bearer $TOKEN"
end

fair_login
curl -fsS -H "$AUTH" $API/auth/me/ | jq '{osm_id, username}'
```

The first time only, make your account an admin:

```fish
set -gx OSM_ID (curl -fsS -H "$AUTH" $API/auth/me/ | jq -r .osm_id)
kubectl -n $NS exec $DEPLOY -c api -- python manage.py shell -c "
from accounts.models import OsmUser
u = OsmUser.objects.get(osm_id=$OSM_ID)
u.is_staff = True; u.is_superuser = True; u.save()
print(u.username, u.is_staff)"
```

## 3. Register the base model

Download the model's STAC item from fAIr-models and pin its images to fixed
digests:

```fish
function ghcr_digest --description "ghcr_digest <repo> <tag>"
    set -l tok (curl -fsS "https://ghcr.io/token?scope=repository:$argv[1]:pull" | jq -r .token)
    curl -fsSI -H "Authorization: Bearer $tok" \
        -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" \
        "https://ghcr.io/v2/$argv[1]/manifests/$argv[2]" | string match -r -i '^docker-content-digest: *(\S+)' | tail -1
end

set -gx IMG ghcr.io/hotosm/fair-models/$MODEL_DIR
set -gx MODEL_SHA (curl -fsS "https://api.github.com/repos/hotosm/fAIr-models/commits?sha=develop&path=models/$MODEL_DIR&per_page=1" | jq -r '.[0].sha')
set -gx TRAIN_DIGEST (ghcr_digest hotosm/fair-models/$MODEL_DIR v1)
set -gx INFER_DIGEST (ghcr_digest hotosm/fair-models/$MODEL_DIR v1-inference)

curl -fsSL https://raw.githubusercontent.com/hotosm/fAIr-models/$MODEL_SHA/models/$MODEL_DIR/stac-item.json \
  | jq --arg t "$IMG@$TRAIN_DIGEST" --arg i "$IMG@$INFER_DIGEST" \
       --arg src "https://github.com/hotosm/fAIr-models/tree/$MODEL_SHA/models/$MODEL_DIR" '
      .assets["mlm:training"].href  = $t
    | .assets["mlm:inference"].href = $i
    | .assets["source-code"].href   = $src' \
  > /tmp/$MODEL.json
```

Register it and wait until it is active. This takes a few minutes the first
time:

```fish
jq -n --slurpfile item /tmp/$MODEL.json '{stac_item: $item[0], category: "buildings"}' \
  | curl -fsS -X POST $API/base-models/ -H "$AUTH" -H 'Content-Type: application/json' -d @- \
  | tee /tmp/bm.json | jq '{id, name, status}'
set -gx BM_ID (jq -r .id /tmp/bm.json)

while true
    set s (curl -fsS -H "$AUTH" $API/base-models/$BM_ID/ | jq -r .status); echo (date +%T) $s
    contains -- $s active failed; and break
    sleep 10
end
set -gx BM_STAC_ID (curl -fsS -H "$AUTH" $API/base-models/$BM_ID/ | jq -r .stac_item_id)
```

Check it:

```fish
curl -fsS https://$MODEL.predict.ai.hotosm.org/health; echo
curl -fsS $STAC/collections/base-models/items/$BM_STAC_ID | jq '.assets | map_values(.href)'
```

Expect `{"status":"ok"}`, and the item's images pinned with `@sha256:`.

## 4. Build a dataset

```fish
jq -n --argjson b "$BBOX" '{type:"Feature", properties:{dataset:null},
  geometry:{type:"Polygon", coordinates:[[[ $b[0],$b[1] ],[ $b[2],$b[1] ],[ $b[2],$b[3] ],[ $b[0],$b[3] ],[ $b[0],$b[1] ]]]}}' \
  | curl -fsS -X POST $API/aois/ -H "$AUTH" -H 'Content-Type: application/json' -d @- \
  | tee /tmp/aoi.json | jq .properties
set -gx AOI_ID (jq -r '.properties.id // .id' /tmp/aoi.json)

jq -n --arg t "e2e-banepa-$RUN" --arg img "$IMAGERY" --argjson aoi "$AOI_ID" '{
  title: $t, description: "e2e test", source_imagery: $img, category: "buildings",
  zoom: 19, aoi_ids: [$aoi], label_tasks: ["semantic-segmentation"],
  label_classes: [{name: "building", classes: ["*"]}],
  keywords: ["building"], label_type: "vector", geometry_type: "polygon"}' \
  | curl -fsS -X POST $API/datasets/build/ -H "$AUTH" -H 'Content-Type: application/json' -d @- \
  | tee /tmp/ds.json | jq '{id, stac_id, status}'
set -gx DS_ID (jq -r .id /tmp/ds.json)
set -gx DS_STAC_ID (jq -r .stac_id /tmp/ds.json)

while true
    set s (curl -fsS -H "$AUTH" $API/datasets/$DS_ID/ | jq -r .status); echo (date +%T) $s
    contains -- $s built failed; and break
    sleep 15
end
```

Expect `built` after a couple of minutes.

## 5. Train

```fish
set -gx LM_NAME sklearn-banepa-e2e-$RUN
jq -n --arg bm "$BM_STAC_ID" --arg ds "$DS_STAC_ID" --arg n "$LM_NAME" '{
  base_model_stac_id: $bm, dataset_stac_id: $ds, model_name: $n,
  overrides: {max_iter: 200}, description: "e2e"}' \
  | curl -fsS -X POST $API/trainings/submit/ -H "$AUTH" -H 'Content-Type: application/json' -d @- \
  | tee /tmp/tr.json | jq '{id, status}'
set -gx TR_ID (jq -r .id /tmp/tr.json)

while true
    set s (curl -fsS -H "$AUTH" $API/trainings/$TR_ID/ | jq -r .status); echo (date +%T) $s
    contains -- $s completed failed stopped cancelled; and break
    sleep 30
end
```

Expect `completed` after a few minutes, which includes starting a training
node. To watch it:

```fish
kubectl -n $PIPE_NS get pods -w
```

Check that MLflow recorded the run:

```fish
set MLU (kubectl -n $NS get secret mlflow-prod-admin-password -o jsonpath='{.data.adminUsername}' | base64 -d)
set MLP (kubectl -n $NS get secret mlflow-prod-admin-password -o jsonpath='{.data.adminPassword}' | base64 -d)
set EXP (curl -fsS -u "$MLU:$MLP" "$MLFLOW_URL/api/2.0/mlflow/experiments/get-by-name?experiment_name=$LM_NAME" | jq -r .experiment.experiment_id)
curl -fsS -u "$MLU:$MLP" -X POST $MLFLOW_URL/api/2.0/mlflow/runs/search \
  -H 'Content-Type: application/json' -d "{\"experiment_ids\":[\"$EXP\"]}" \
  | jq '.runs[] | {status: .info.status, metrics: [.data.metrics[].key]}'
set -e MLP
```

Expect a `FINISHED` run with metrics such as `building_iou`.

## 6. Publish

```fish
curl -fsS -X POST $API/trainings/$TR_ID/publish/ -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"description": "e2e"}' | tee /tmp/pub.json | jq
set -gx LM_STAC_ID (jq -r .local_model_stac_id /tmp/pub.json)

curl -fsS $STAC/collections/local-models/items/$LM_STAC_ID | jq '{id, base: .properties["fair:base_model_id"], assets: (.assets | map_values(.href))}'
curl -sSL -o /dev/null -w '%{http_code}\n' (curl -fsS $STAC/collections/local-models/items/$LM_STAC_ID | jq -r .assets.model.href)
```

Expect a `local-models` item linked to the base model, and `200` for the ONNX
download.

## 7. Predict through the API

```fish
jq -n --arg m "$LM_STAC_ID" --arg img "$IMAGERY" --argjson b "$BBOX" '{
  model_stac_id: $m, image_uri: $img, bbox: $b, zoom: 19,
  params: {confidence_threshold: 0.5}, description: "e2e"}' \
  | curl -fsS -X POST $API/predictions/submit/ -H "$AUTH" -H 'Content-Type: application/json' -d @- \
  | tee /tmp/pred.json | jq '{id, status}'
set -gx PRED_ID (jq -r .id /tmp/pred.json)

while true
    curl -fsS -H "$AUTH" $API/predictions/$PRED_ID/ > /tmp/pred-status.json
    echo (date +%T) (jq -c '{status, results_ready}' /tmp/pred-status.json)
    jq -e '.results_ready == true or .status == "failed"' /tmp/pred-status.json >/dev/null; and break
    sleep 30
end

curl -fsS -H "$AUTH" $API/predictions/$PRED_ID/result/ > /tmp/res.json
curl -fsSL (jq -r .geojson /tmp/res.json) | jq '.features | length'
curl -sS -o /dev/null -w '%{http_code}\n' (jq -r .pmtiles /tmp/res.json)
curl -sS -o /dev/null -w '%{http_code}\n' (jq -r .fgb /tmp/res.json)
```

Expect some features and `200` for both downloads. The result links only work
with a normal download (GET), so `curl -I` returns `403`.

## 8. Predict live through Knative

```fish
curl -fsS $STAC/collections/local-models/items/$LM_STAC_ID > /tmp/lm-item.json
set BASE_ID (jq -r '.properties["fair:base_model_id"]' /tmp/lm-item.json)
set ENDPOINT (curl -fsS $STAC/collections/base-models/items/$BASE_ID | jq -r '.assets["mlm:inference-endpoint"].href')
set PARAMS (jq -c '.properties["mlm:hyperparameters"] | with_entries(select(.key|startswith("inference.")) | .key |= ltrimstr("inference."))' /tmp/lm-item.json)

jq -n --arg m (jq -r .assets.model.href /tmp/lm-item.json) --arg img "$IMAGERY" --argjson p "$PARAMS" '{
  model_uri: $m, image_uri: $img, bbox: [85.5185, 27.6325, 85.5205, 27.6345], zoom: 19, params: $p}' \
  | curl -sS -X POST "$ENDPOINT" -H 'Content-Type: application/json' -d @- \
    -w '\nHTTP %{http_code} in %{time_total}s\n' -o /tmp/live.geojson
jq '.features | length' /tmp/live.geojson
```

Expect `HTTP 200` and some features. The first request can take a few seconds
while the service starts from zero.

## 9. Check the Knative reconciler (optional)

The reconciler runs every 15 minutes and keeps Knative in line with STAC. To
run it now, and to check that a deleted service comes back:

```fish
kubectl -n $NS create job --from=$CRON reconcile-$RUN
kubectl -n $NS wait --for=condition=complete job/reconcile-$RUN --timeout=15m
kubectl -n $NS logs job/reconcile-$RUN | tail -1

kubectl -n $KN_NS delete ksvc $MODEL
kubectl -n $NS create job --from=$CRON reconcile-$RUN-2
kubectl -n $NS wait --for=condition=complete job/reconcile-$RUN-2 --timeout=15m
curl -fsS https://$MODEL.predict.ai.hotosm.org/health; echo
```

Expect `"failed": []` in the log, and `{"status":"ok"}` after the service is
rebuilt.

## GPU training

Training uses a GPU when the base model declares `mlm:accelerator: cuda`.
Karpenter then starts a GPU node for the run and removes it afterwards. To
test this with `dinov3s-buildings`:

```fish
set -gx MODEL dinov3s-buildings
set -gx MODEL_DIR dinov3s_buildings
```

1. Run section 3 up to and including the `curl … > /tmp/$MODEL.json` command.
   Before registering, mark the item as a GPU model:

   ```fish
   jq '.properties["mlm:accelerator"] = "cuda" | .properties["mlm:accelerator_count"] = 1' /tmp/$MODEL.json > /tmp/gpu.json
   mv /tmp/gpu.json /tmp/$MODEL.json
   ```

2. Register it with the rest of section 3.
3. Run section 5 using `set -gx LM_NAME dinov3-banepa-gpu-$RUN` and
   `overrides: {epochs: 1, batch_size: 4, tune_postprocess_trials: 2}`.
4. Watch the GPU node start and check the step pod uses it:

   ```fish
   kubectl get nodeclaims -w
   set POD (kubectl -n $PIPE_NS get pods -l step_name=train-model -o name | tail -1)
   kubectl -n $PIPE_NS exec $POD -- python -c "import torch; print(torch.cuda.is_available())"
   ```

Expect a new `gpu-autoscale-fair` node claim, and `True`.

## Clean up

```fish
kubectl -n $NS delete job reconcile-$RUN reconcile-$RUN-2 --ignore-not-found
```

The test model, dataset and predictions stay in fAIr. There is no delete
endpoint for base models yet.
