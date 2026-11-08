# fAIr end-to-end test

A manual run through the whole model workflow using the API: register a base model,
build a dataset, train, publish, then predict (via the API and live via Knative).

On staging, `just test e2e` in the fAIr repo does all of this for you (`test.py`). Use
this guide for production, or to debug a single step.

> [!NOTE]
> You need `kubectl` on the HOT cluster, `curl`, `jq` and fish. Run everything in one
> shell. Env names are in the [environments table](README.md#environments).

## 1. Set up

Staging (MLflow has no ingress, so we port-forward it):

```fish
set -gx WEB https://stage.ai.hotosm.org
set -gx API https://stage.ai.hotosm.org/api/v1
set -gx STAC https://stac.stage.ai.hotosm.org/stac
set -gx NS fair-staging
set -gx PIPE_NS zenml-pipelines-stage
set -gx DEPLOY deployment/fair-backend
set -gx CRON cronjob/fair-backend-knative-reconcile
set -gx MLFLOW_SECRET mlflow-admin-password
set -gx MLFLOW_URL http://localhost:5000
set -gx KN_PREFIX staging-
kubectl -n $NS port-forward svc/mlflow 5000:5000 >/dev/null &
```

Production:

```fish
set -gx WEB https://ai.hotosm.org
set -gx API https://api.ai.hotosm.org/api/v1
set -gx STAC https://stac.ai.hotosm.org/stac
set -gx NS fair-prod
set -gx PIPE_NS zenml-pipelines-prod
set -gx DEPLOY deployment/fair-backend-backend
set -gx CRON cronjob/fair-backend-backend-knative-reconcile
set -gx MLFLOW_SECRET mlflow-prod-admin-password
set -gx MLFLOW_URL https://mlflow.ai.hotosm.org
set -gx KN_PREFIX ''
```

Then, for either:

```fish
set -gx KN_NS fair-knative
set -gx RUN (date +%Y%m%d%H%M)
set -gx MODEL sklearn-rgb-segmentation
set -gx MODEL_DIR sklearn_rgb_segmentation
set -gx ITEM_URL https://raw.githubusercontent.com/hotosm/fAIr-models/refs/heads/develop/models/$MODEL_DIR/stac-item.json
set -gx IMAGERY 'https://api.imagery.hotosm.org/raster/collections/openaerialmap/items/62d86c65d8499800053796c4/tiles/WebMercatorQuad/{z}/{x}/{y}?assets=visual'
set -gx BBOX '[85.51678, 27.63133, 85.52323, 27.63743]'

curl -fsS $API/health/ | jq
```

Expect `postgresql`, `s3`, `stac_api` and `zenml` to be `true`.

## 2. Log in

Log in at `$WEB`. Copy the `hanko` cookie from the browser's developer tools
(Application > Cookies), and paste it when prompted:

```fish
read -s -P "Paste hanko cookie: " raw; echo
set -gx TOKEN (string match -r "eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" -- $raw)
set -gx AUTH "Authorization: Bearer $TOKEN"
curl -fsS -H "$AUTH" $API/auth/me/ | jq '{osm_id, username}'
```

Make your account an admin. This is needed once on production, and on every new staging PR,
because the staging database is fresh each time:

```fish
set -gx OSM_ID (curl -fsS -H "$AUTH" $API/auth/me/ | jq -r .osm_id)
kubectl -n $NS exec $DEPLOY -c api -- python manage.py shell -c "
from accounts.models import OsmUser
OsmUser.objects.filter(osm_id=$OSM_ID).update(is_staff=True, is_superuser=True)
print(OsmUser.objects.get(osm_id=$OSM_ID).username)"
```

## 3. Register the base model

The backend mirrors the weights, pins the images to digests and deploys the
Knative service. This takes a few minutes the first time.

```fish
jq -n --arg u $ITEM_URL '{stac_item_url: $u, category: "buildings"}' \
  | curl -fsS -X POST $API/base-models/ -H "$AUTH" -H 'Content-Type: application/json' -d @- \
  | tee /tmp/bm.json | jq '{id, name, status}'
set -gx BM_ID (jq -r .id /tmp/bm.json)

while true
    curl -fsS -H "$AUTH" $API/base-models/$BM_ID/ > /tmp/bm.json
    set s (jq -r .status /tmp/bm.json); echo (date +%T) $s
    contains -- $s active failed; and break
    sleep 10
end
jq -r .error /tmp/bm.json
set -gx BM_STAC_ID (jq -r .stac_item_id /tmp/bm.json)

curl -fsS https://$KN_PREFIX$MODEL.predict.ai.hotosm.org/health; echo
curl -fsS $STAC/collections/base-models/items/$BM_STAC_ID | jq '.assets | map_values(.href)'
```

Expect `active`, `{"status":"ok"}`, images pinned with `@sha256:`, and `checkpoint`
and `model` under `$API/artifacts/`.

## 4. Build a dataset

```fish
jq -n --argjson b "$BBOX" '{type:"Feature", properties:{dataset:null},
  geometry:{type:"Polygon", coordinates:[[[ $b[0],$b[1] ],[ $b[2],$b[1] ],[ $b[2],$b[3] ],[ $b[0],$b[3] ],[ $b[0],$b[1] ]]]}}' \
  | curl -fsS -X POST $API/aois/ -H "$AUTH" -H 'Content-Type: application/json' -d @- \
  | tee /tmp/aoi.json | jq .properties
set -gx AOI_ID (jq -r .properties.id /tmp/aoi.json)

jq -n --arg t "e2e-banepa-$RUN" --arg img "$IMAGERY" --argjson aoi "$AOI_ID" '{
  title: $t, description: "e2e test", source_imagery: $img, category: "buildings",
  zoom: 19, aoi_ids: [$aoi], label_tasks: ["semantic-segmentation"],
  label_classes: [{name: "building", classes: ["*"]}],
  keywords: ["building", "polygon"], label_type: "vector", geometry_type: "polygon"}' \
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
set -gx LM_NAME e2e-banepa-$RUN
jq -n --arg bm "$BM_STAC_ID" --arg ds "$DS_STAC_ID" --arg n "$LM_NAME" '{
  base_model_stac_id: $bm, dataset_stac_id: $ds, model_name: $n}' \
  | curl -fsS -X POST $API/trainings/submit/ -H "$AUTH" -H 'Content-Type: application/json' -d @- \
  | tee /tmp/tr.json | jq '{id, status}'
set -gx TR_ID (jq -r .id /tmp/tr.json)

while true
    set s (curl -fsS -H "$AUTH" $API/trainings/$TR_ID/ | jq -r .status); echo (date +%T) $s
    contains -- $s completed failed stopped cached retried; and break
    sleep 30
end
```

Expect `completed` after a few minutes, including node start-up. To watch:
`kubectl -n $PIPE_NS get pods -w`.

Check the run status, logs and MLflow record:

```fish
set -gx RUN_ID (curl -fsS -H "$AUTH" $API/trainings/$TR_ID/ | jq -r .zenml_run_id)
curl -fsS -H "$AUTH" $API/trainings/runs/$RUN_ID/status/ | jq '{status, is_terminal}'
curl -fsS -H "$AUTH" $API/trainings/runs/$RUN_ID/logs/ | jq length

set MLU (kubectl -n $NS get secret $MLFLOW_SECRET -o jsonpath='{.data.adminUsername}' | base64 -d)
set MLP (kubectl -n $NS get secret $MLFLOW_SECRET -o jsonpath='{.data.adminPassword}' | base64 -d)
set EXP (curl -fsS -u "$MLU:$MLP" "$MLFLOW_URL/api/2.0/mlflow/experiments/get-by-name?experiment_name=$LM_NAME" | jq -r .experiment.experiment_id)
curl -fsS -u "$MLU:$MLP" -X POST $MLFLOW_URL/api/2.0/mlflow/runs/search \
  -H 'Content-Type: application/json' -d "{\"experiment_ids\":[\"$EXP\"]}" \
  | jq '.runs[] | {status: .info.status, metrics: [.data.metrics[].key]}'
set -e MLP
```

Expect `completed`, `true`, some log entries, and a `FINISHED` MLflow run with metrics.

## 6. Publish

```fish
curl -fsS -X POST $API/trainings/$TR_ID/publish/ -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"description": "e2e", "title": "e2e promoted model"}' | tee /tmp/pub.json | jq
set -gx LM_STAC_ID (jq -r .local_model_stac_id /tmp/pub.json)

curl -fsS $STAC/collections/local-models/items/$LM_STAC_ID > /tmp/lm-item.json
jq '{id, base: .properties["fair:base_model_id"], assets: (.assets | map_values(.href))}' /tmp/lm-item.json
curl -sSL -o /dev/null -w '%{http_code}\n' (jq -r .assets.model.href /tmp/lm-item.json)
```

Expect a `local-models` item linked to the base model, and `200` for the ONNX download.

## 7. Predict through the API

```fish
jq -n --arg m "$LM_STAC_ID" --arg img "$IMAGERY" --argjson b "$BBOX" '{
  model_stac_id: $m, image_uri: $img, bbox: $b, zoom: 19,
  params: {confidence_threshold: 0.25}}' \
  | curl -fsS -X POST $API/predictions/submit/ -H "$AUTH" -H 'Content-Type: application/json' -d @- \
  | tee /tmp/pred.json | jq '{id, status}'
set -gx PRED_ID (jq -r .id /tmp/pred.json)

while true
    curl -fsS -H "$AUTH" $API/predictions/$PRED_ID/ > /tmp/pred-status.json
    echo (date +%T) (jq -c '{status, results_ready}' /tmp/pred-status.json)
    jq -e '.results_ready == true or .status == "failed" or .status == "stopped"' /tmp/pred-status.json >/dev/null; and break
    sleep 30
end

curl -fsS -H "$AUTH" $API/predictions/$PRED_ID/result/ > /tmp/res.json
curl -fsSL (jq -r .geojson /tmp/res.json) | jq '.features | length'
curl -sS -o /dev/null -w '%{http_code}\n' (jq -r .pmtiles /tmp/res.json)
curl -sS -o /dev/null -w '%{http_code}\n' (jq -r .fgb /tmp/res.json)
```

Expect some features and `200` for both downloads. The result links are presigned
for GET only, so `curl -I` returns `403`.

## 8. Predict live through Knative

```fish
set BASE_ID (jq -r '.properties["fair:base_model_id"]' /tmp/lm-item.json)
set ENDPOINT (curl -fsS $STAC/collections/base-models/items/$BASE_ID | jq -r '.assets["mlm:inference-endpoint"].href')
set PARAMS (jq -c '.properties["mlm:hyperparameters"] | with_entries(select(.key|startswith("inference.")) | .key |= ltrimstr("inference."))' /tmp/lm-item.json)
echo $ENDPOINT

jq -n --arg m (jq -r .assets.model.href /tmp/lm-item.json) --arg img "$IMAGERY" --argjson p "$PARAMS" '{
  model_uri: $m, image_uri: $img, bbox: [85.5185, 27.6325, 85.5205, 27.6345], zoom: 19, params: $p}' \
  | curl -sS -X POST "$ENDPOINT" -H 'Content-Type: application/json' -d @- \
    -w '\nHTTP %{http_code} in %{time_total}s\n' -o /tmp/live.geojson
jq '.features | length' /tmp/live.geojson
```

Expect `HTTP 200` and some features. On staging, the endpoint must start with
`https://staging-`. The first request can take a few seconds while the service starts.

## 9. Knative reconciler (optional)

The reconciler re-applies Knative services from STAC every 15 minutes. To run it now:

```fish
kubectl -n $NS create job --from=$CRON reconcile-$RUN
kubectl -n $NS wait --for=condition=complete job/reconcile-$RUN --timeout=15m
kubectl -n $NS logs job/reconcile-$RUN | tail -1
```

Expect `"failed": []`.

Production only: check that a deleted service comes back. Staging shares these services
with production, so never delete them from staging.

```fish
kubectl -n $KN_NS delete ksvc $MODEL
kubectl -n $NS create job --from=$CRON reconcile-$RUN-2
kubectl -n $NS wait --for=condition=complete job/reconcile-$RUN-2 --timeout=15m
curl -fsS https://$MODEL.predict.ai.hotosm.org/health; echo
```

## GPU training

Training uses a GPU when the base model declares `mlm:accelerator: cuda`. Karpenter
starts a GPU node for the run and removes it afterwards. To test with `dinov3s-buildings`:

```fish
set -gx MODEL dinov3s-buildings
set -gx MODEL_DIR dinov3s_buildings
curl -fsSL https://raw.githubusercontent.com/hotosm/fAIr-models/refs/heads/develop/models/$MODEL_DIR/stac-item.json \
  | jq '.properties["mlm:accelerator"] = "cuda" | .properties["mlm:accelerator_count"] = 1' > /tmp/$MODEL.json
jq -n --slurpfile item /tmp/$MODEL.json '{stac_item: $item[0], category: "buildings"}' \
  | curl -fsS -X POST $API/base-models/ -H "$AUTH" -H 'Content-Type: application/json' -d @- \
  | tee /tmp/bm.json | jq '{id, name, status}'
set -gx BM_ID (jq -r .id /tmp/bm.json)
```

1. Wait for registration with the loop in section 3.
2. Run section 5 with `set -gx LM_NAME dinov3-banepa-gpu-$RUN`, and add
   `overrides: {epochs: 1, batch_size: 4, tune_postprocess_trials: 2}` to the request.
3. Watch the GPU node start, and check that the step pod uses it:

   ```fish
   kubectl get nodeclaims -w
   set POD (kubectl -n $PIPE_NS get pods -l step_name=train-model -o name | tail -1)
   kubectl -n $PIPE_NS exec $POD -- python -c "import torch; print(torch.cuda.is_available())"
   ```

Expect a new `gpu-autoscale-fair` node claim, and `True`.

## Clean up

```fish
kubectl -n $NS delete job reconcile-$RUN reconcile-$RUN-2 --ignore-not-found
jobs -p | xargs -r kill # staging MLflow port-forward
```

The test model, dataset and predictions stay in fAIr. There is no delete endpoint for
base models yet.
