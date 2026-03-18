# k8s Cluster Maintenance

## Worker nodes disk filling up

- The worker nodes pull images over time that they often
  no longer need (e.g. app upgrades).
- These images can fill up the disk space.
- To clean them:
  1. Access AWS EKS and go to Compute section.
  2. Click on a node, then click through to the EC2 instance.
  3. Connect using SSM Session Manager (the only option).
  4. Run cleanup commands for containerd:

  ```bash
  sudo nerdctl image prune -a
  sudo nerdctl system prune
  ```
