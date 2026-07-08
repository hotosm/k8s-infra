# Deploying Apps With GitOps and ArgoCD

<iframe
  src="https://drive.google.com/file/d/1D9XJPDZ9fKZGDbsEz5Tzwiu8tdz0mA7y/preview"
  width="100%"
  height="480"
  allow="autoplay; fullscreen"
  allowfullscreen
></iframe>

## Staging deployments using ApplicationSet PR generator

An `ApplicationSet` with a `pullRequest` generator watches an app repo for PRs
matching `head=staging → base=main` and spins up an on-demand deploy per PR.

Flow:

1. **PR generator polls GitHub** every `requeueAfterSeconds` (300s) for PRs
   matching the head/base filters.
2. **On each poll** it returns `{ number, head_sha, ... }`. Pushing a new
   commit to `staging` changes `head_sha`.
3. **Template re-renders** the Application with the new `head_sha`:
     - `sources[0].targetRevision: {{ .head_sha }}` - chart is re-fetched from
       that exact commit, so chart changes in the PR get exercised too.
     - `helm.parameters[image.tag]: sha-{{ .head_sha }}` - Deployment's
       container image tag changes.
4. **Argo diff** detects the Application spec changed → syncs → Deployment
   PodSpec changes → k8s rolls the pod cleanly. No mutable tag race, no
   annotation hack.
5. **CI on the app repo** must push `…:sha-<long-sha>` on every commit to the
   `staging` branch (via `docker/metadata-action` with
   `type=sha,format=long`). Argo assumes the tag exists by the time it tries
   to pull.

Closing/merging the PR removes it from the generator's result set → Argo
deletes the Application → `resources-finalizer.argoproj.io` prunes the
namespace and everything in it.

See `apps/staging/hot-website.yaml` for a working example.

## Production deployments using Argo Image Updater

