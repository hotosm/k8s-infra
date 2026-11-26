provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.cluster.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.cluster.name]
    }
  }
}

resource "helm_release" "ingress" {
  name             = "ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = var.nginx_ingress_version

  set {
    name  = "controller.enableLatencyMetrics"
    value = true
  }

  set {
    name  = "controller.metrics.enabled"
    value = true
  }

  set {
    name  = "controller.metrics.service.annotations.prometheus\\.io/scrape"
    value = "true"
    type  = "string"
  }

  set {
    name  = "controller.metrics.service.annotations.prometheus\\.io/port"
    value = "10254"
    type  = "string"
  }

  # 2 replicas spread across zones, so a rollout always has one pod serving
  set {
    name  = "controller.replicaCount"
    value = 2
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "256Mi"
    type  = "string"
  }

  # Keep accepting connections for 15s after a pod is told to stop
  set {
    name  = "controller.extraArgs.shutdown-grace-period"
    value = "15"
    type  = "string"
  }

  set {
    name  = "controller.topologySpreadConstraints[0].maxSkew"
    value = 1
  }

  set {
    name  = "controller.topologySpreadConstraints[0].topologyKey"
    value = "topology.kubernetes.io/zone"
    type  = "string"
  }

  set {
    name  = "controller.topologySpreadConstraints[0].whenUnsatisfiable"
    value = "ScheduleAnyway"
    type  = "string"
  }

  set {
    name  = "controller.topologySpreadConstraints[0].labelSelector.matchLabels.app\\.kubernetes\\.io/name"
    value = "ingress-nginx"
    type  = "string"
  }

  set {
    name  = "controller.topologySpreadConstraints[0].labelSelector.matchLabels.app\\.kubernetes\\.io/instance"
    value = "ingress"
    type  = "string"
  }

  set {
    name  = "controller.topologySpreadConstraints[0].labelSelector.matchLabels.app\\.kubernetes\\.io/component"
    value = "controller"
    type  = "string"
  }

  # Patched controller built from the Chainguard fork
  # Our image is on images/ingress-nginx
  set {
    name  = "controller.image.registry"
    value = "ghcr.io"
    type  = "string"
  }

  set {
    name  = "controller.image.image"
    value = "hotosm/k8s-infra/ingress-nginx/controller"
    type  = "string"
  }

  set {
    name  = "controller.image.tag"
    value = "v1.15.16"
    type  = "string"
  }

  set {
    name  = "controller.image.digest"
    value = "sha256:6e67c2497e83a13cf5ff171d736675ed2d659433580e129f9f1c029e5726164d"
    type  = "string"
  }

  wait = true
  depends_on = [
    aws_eks_cluster.cluster
  ]
}

##############################
# SUPPORT OPTIONS
##############################

resource "helm_release" "prometheus" {
  count            = var.enable_support_helm_charts ? 1 : 0
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  namespace        = "support"
  create_namespace = true
  version          = var.prometheus_version

  set {
    name  = "alertmanager.enabled"
    value = false
  }

  set {
    name  = "pushgateway.enabled"
    value = false
  }

  set {
    name  = "server.persistentVolume.size"
    value = var.prometheus_disk_size
  }

  set {
    name  = "server.retention"
    value = "${var.prometheus_metrics_retention_days}d"
  }

  set {
    name  = "server.ingress.enabled"
    value = true
  }

  set {
    name  = "server.ingress.hosts[0]"
    value = var.prometheus_hostname
  }

  set {
    # Double \\ is neded so the entire last part of the name is used as key
    name  = "server.ingress.annotations.kubernetes\\.io/ingress\\.class"
    value = "nginx"
  }

  set {
    # We have a persistent disk attached, so the default (RollingUpdate)
    # can sometimes get 'stuck' and require pods to be manually deleted.
    name  = "strategy.type"
    value = "Recreate"
  }
  # wait = true
  depends_on = [
    aws_eks_cluster.cluster
  ]
}


resource "helm_release" "metrics-server" {
  count      = var.enable_support_helm_charts ? 1 : 0
  name       = "metrics-server"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "metrics-server"
  version    = var.metrics_server_version
  namespace  = "kube-system"

  wait = true

  depends_on = [
    aws_eks_cluster.cluster
  ]
}
