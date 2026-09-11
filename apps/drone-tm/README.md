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

## Optional: plan.drone.hotosm.org

An installable PWA either way, but its own host gives the service worker root
scope instead of `/plan/`. Decide before telling anyone to install it - the two
are separate origins, so an install and its saved plans do not carry across.

Uncomment `subdomainApps` in `helm/values.yaml`, then, because the chart sets
aliases only when it *creates* a distribution:

1. ACM cert in **us-east-1** covering the host. Certs are immutable, so if it is
   missing, request one covering both names and update `acmCertificateArn`:

   ```sh
   aws acm describe-certificate --region us-east-1 \
     --certificate-arn arn:aws:acm:us-east-1:670261699094:certificate/e6eaaa9c-0de8-4222-b8f9-0e8c3e56f813 \
     --query 'Certificate.SubjectAlternativeNames'
   ```

2. Add the host to the distribution's aliases.
3. Route53 A-alias to the distribution. external-dns watches Ingress and Service
   only, so it will not create this.
4. Set `runtimeEnv.VITE_FLIGHT_PLANNER_URL` so the navbar points there.
