cluster_name  = "HOTOSM Talos Prod"
ccm           = false

control_plane = {
  instance_type      = "t3.small"
  num_instances      = 3
  config_patch_files = []
  tags               = {}
}

worker_groups = [
  {
    name               = "cpu"
    instance_type      = "c5.large"
    num_instances      = 1
    config_patch_files = []
    tags               = {}
  }
]

extra_tags = {
  project     = "devops"
  tool        = "all"
  environment = "prod"
  maintainer  = "sam.woodcock@hotosm.org"
  repository  = "github.com/hotosm/k8s-infra"
  terraform   = true
}

vpc_cidr                     = "172.16.0.0/16"
talos_api_allowed_cidr      = "0.0.0.0/0"
kubernetes_api_allowed_cidr = "0.0.0.0/0"
config_patch_files          = []
