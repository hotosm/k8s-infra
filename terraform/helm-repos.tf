provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.cluster.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.cluster.name]
    }
  }
}

resource "helm_release" "autoscaler" {
  name             = "cluster-autoscaler"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  version          = var.cluster_autoscaler_version
  namespace        = "cluster-autoscaler"
  create_namespace = true

  set {
    name  = "autoDiscovery.clusterName"
    value = aws_eks_cluster.cluster.name
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    # Double escaping needed as otherwise . is inteprerted as nesting
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler.arn
  }

  wait = true

  depends_on = [
    aws_eks_cluster.cluster
  ]
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

  wait = true
  depends_on = [
    aws_eks_cluster.cluster
  ]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = var.cert_manager_version

  set {
    # We can manage CRDs from inside Helm itself, no need for a separate kubectl apply
    name  = "installCRDs"
    value = true
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