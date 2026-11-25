# ingress-nginx image

Builds the ingress-nginx controller image from the [Chainguard fork](https://github.com/chainguard-forks/ingress-nginx),
since upstream ingress-nginx is archived and no longer gets security fixes.

The fork patches nginx for NGINX2Root (CVE-2026-123007) and other CVEs, but those patches live in the nginx base image
source. The fork's default build still uses the old unpatched base (`registry.k8s.io/ingress-nginx/nginx:v2.2.8`).
This builds the patched base first and then the controller on top of it.

Other changes compared to the fork's build:

- Go 1.26.11 instead of 1.26.2
- the build container gets an empty `HOME` (the fork's script mounts `~/.kube` into it)
- the controller is tagged with the real version (the fork's `TAG` file still says v1.15.5)

## Versions

See [versions.env](versions.env). Currently controller v1.15.16, nginx 1.27.1 with 59 patches, Alpine 3.23, Go 1.26.11.
Works with chart 4.15.1 and Kubernetes 1.31 to 1.35.

## Images

```
ghcr.io/hotosm/k8s-infra/ingress-nginx/nginx:v2.2.26
ghcr.io/hotosm/k8s-infra/ingress-nginx/controller:v1.15.16
```

Tags follow the ingress-nginx versions, CI also adds `sha-<commit>`. Deploy by digest, a rebuild replaces the tag.

```yaml
controller:
  image:
    registry: ghcr.io
    image: hotosm/k8s-infra/ingress-nginx/controller
    tag: v1.15.16
    digest: sha256:...
```

## Build

Needs Docker with buildx, git, jq and trivy.

```bash
./build.sh           # clone the fork, build the base and controller images
./build.sh verify    # check versions, base layers and trivy (no fixable critical/high)
./build.sh push      # push both images, controller is rebuilt on the pushed base digest
./build.sh clean
```

Set `REGISTRY` to push somewhere else, e.g. `REGISTRY=ghcr.io/<user>/ingress-nginx`.

The base build fails if any nginx patch doesn't apply cleanly. Trivy can't see nginx since it's compiled from source,
so `work/out/patches.txt` is the record of what was applied.

In CI ([ingress-nginx-image.yml](../../.github/workflows/ingress-nginx-image.yml)), pull requests that change this
directory build and verify. Running the workflow manually on `main` with `push` pushes to GHCR. A weekly run fails
when the fork has a newer release. Nothing here deploys anything, the image is used by `helm_release.ingress` in
`terraform/` once its digest is set there.

## Updating

1. Check what changed in the fork (`images/nginx/rootfs/patches`, `GOLANG_VERSION`).
2. Update `versions.env`.
3. `./build.sh clean && ./build.sh && ./build.sh verify`, then test the image before changing the digest anywhere.
