# k8s Cluster Maintenance

## Connecting to the worker nodes

1. Access AWS EKS and go to Compute section.
2. Click on a node, then click through to the EC2 instance.
3. Connect using SSM Session Manager (the only option).

## Worker nodes disk filling up

- The worker nodes pull images over time that they often
  no longer need (e.g. app upgrades).
- These images can fill up the disk space.
- To clean them:

  ```bash
  sudo nerdctl image prune -a
  sudo nerdctl system prune

  SRC_IMAGE="ghcr.io/containerd/pause"
  echo "Using pause image: $SRC_IMAGE"
  sudo ctr -n k8s.io images tag "$SRC_IMAGE" localhost/kubernetes/pause:latest
  sudo systemctl restart containerd
  sudo systemctl restart kubelet
  ```

## Cleaning unused images manually

- Once you have an open session to the machine,
  it's as simple as:

  ```bash
  nerdctl image rm xxx
  ```
