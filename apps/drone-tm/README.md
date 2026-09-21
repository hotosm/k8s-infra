# Drone TM

Deploys from the chart the app repo publishes. Creating a release in
`hotosm/drone-tm` bumps chart version and appVersion together, and the Argo app
tracks `targetRevision: "*"`, so a release is what promotes prod.

The frontend is not served from the cluster. A Helm Job syncs the frontend
image's `dist/` to `s3://dronetm-prod-frontend/<appVersion>/` behind
CloudFront; the Ingress here only serves `api.drone.hotosm.org`.

The flight planner is built into that image at `dist/plan` and served at
`drone.hotosm.org/plan`, linked from the main app's navbar. Nothing extra to
deploy.

It stays on `drone.hotosm.org` rather than a host of its own because it reads
the session token the main app stores, which is per-origin. Moving it would
leave it working, but only as a standalone tool: deep links from a project or
task could no longer prefill the area.
