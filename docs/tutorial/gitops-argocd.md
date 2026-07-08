# Deploying Apps With GitOps and ArgoCD

<iframe
  src="https://drive.google.com/file/d/1D9XJPDZ9fKZGDbsEz5Tzwiu8tdz0mA7y/preview"
  width="100%"
  height="480"
  allow="autoplay; fullscreen"
  allowfullscreen
></iframe>

## Staging deployments

- Apps under `apps/staging/` are deployed automatically each time a PR
is made `staging → main`. They are deleted when the PR closes.
- The app repo must build an image on every **push** to `staging`, tagged with
the long commit sha. Using `hotosm/gh-workflows` `image_build` workflow
will handle this for you.
- The generator polls GitHub every 300s and renders the template with
`head_sha` (tip of `staging`) in two places:
  - `sources[0].targetRevision: "{{ .head_sha }}"` - chart is fetched from
    that commit, so chart changes in the PR are exercised too.
  - `helm.parameters[image.tag]: "sha-{{ .head_sha }}"` - Deployment points
    at the image CI built for that commit.
- Each push to `staging` will deploy the latest changes for testing.
- To sync production data to the database or staging S3 bucket, do a
  manual sync.

!!! warning

        Only a single staging → main PR should be opened
        at a time!

        Otherwise there will be conflict trying to deploy
        the same app twice.

See `apps/staging/hot-website.yaml` for an example.

## Production deployments

We have an arbitrary distinction between stable apps, and apps
still under development.

Our most stable and widely used app is Tasking Manager, so we
treat this differently to other applications in our stack.

### Stable apps

- A few apps under `apps/` require specific chart version pinning to
  deploy.
- The extra manual step helps to make new deployments a more slow
  and considered process, reducing the chances of breaking prod.
- The chart pinned specifies the `appVersion` to deploy (unless
  overriden in values.yaml).

### Apps under development

- Most apps under `apps/` auto-deploy on **GitHub release** of the app
  repo.
- Chart `targetRevision` is set to `"*"`, so Argo picks the highest
  published chart version on each sync.
- Chart templates default `image.tag` to `.Chart.AppVersion`. Cutting a
  release bumps `Chart.yaml`'s `version` + `appVersion` together, so the
  new chart carries its own image tag - both are updated together.
- Rollback: pin `targetRevision` to the previous chart version in a PR.

See `apps/drone-tm.yaml` for an example.
