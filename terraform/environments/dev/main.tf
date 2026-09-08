provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# --- Réseau ---
# Module officiel et très largement utilisé par la communauté Terraform
# (des milliers de projets en production) plutôt qu'un VPC réécrit à la main :
# c'est aussi la pratique standard en entreprise (ne pas réinventer une brique
# aussi standard et aussi facile à mal sécuriser qu'un VPC).
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  # Une seule NAT Gateway (et non une par zone de disponibilité) : réduit le
  # coût d'environ moitié pour un environnement de dev/démo, au prix d'un point
  # de défaillance unique inacceptable en production mais très bien pour ce cas.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # VPC Flow Logs : journalise tout le trafic réseau (accepté/rejeté) au niveau
  # du VPC dans CloudWatch Logs — remonté par tfsec (aws-ec2-require-vpc-flow-logs-for-all-vpcs),
  # corrigé ici plutôt qu'accepté comme risque : la visibilité réseau est
  # précieuse en cas d'investigation d'incident, et le coût reste marginal.
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = 7

  # Tags requis par le contrôleur AWS Load Balancer / l'auto-scaler EKS pour
  # savoir quels sous-réseaux utiliser automatiquement.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

locals {
  cluster_name = "${var.project_name}-eks"
}

# --- Cluster Kubernetes managé (EKS) ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.2"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Accès à l'API du cluster : public MAIS restreint à des IP explicitement
  # autorisées (voir variable admin_cidr_blocks), plutôt que privé pur (qui
  # demanderait un VPN/bastion, hors scope d'une démo) ou public ouvert à tous
  # (dangereux : n'importe qui pourrait tenter de s'authentifier sur l'API).
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.admin_cidr_blocks
  cluster_endpoint_private_access      = true

  # Logs d'audit du control plane (qui a fait quoi sur l'API Kubernetes),
  # envoyés dans CloudWatch Logs — remonté par tfsec
  # (aws-eks-enable-control-plane-logging), corrigé plutôt qu'accepté : c'est
  # la source de logs la plus importante pour investiguer un incident de
  # sécurité sur le cluster.
  cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = 7

  # Chiffrement des secrets Kubernetes (etcd) avec une clé KMS dédiée.
  cluster_encryption_config = {
    resources = ["secrets"]
  }

  enable_cluster_creator_admin_permissions = true

  # Gérer explicitement les add-ons EKS (plutôt que de laisser leurs versions
  # "bundled" implicites) permet notamment d'activer l'application réelle des
  # NetworkPolicy par le VPC CNI.
  #
  # Piège découvert en le testant réellement sur ce projet (voir le rapport
  # explicatif) : sur EKS, avec le CNI par défaut, les objets NetworkPolicy
  # (k8s/base/networkpolicy.yaml) sont acceptés par l'API Kubernetes sans
  # erreur, mais ne sont PAS appliqués tant que cette option n'est pas activée
  # explicitement — un pod dans un autre namespace pouvait toujours joindre le
  # service malgré une policy de refus par défaut. `enableNetworkPolicy` active
  # le contrôleur qui traduit chaque NetworkPolicy en règles eBPF réellement
  # appliquées par l'agent réseau sur chaque nœud.
  cluster_addons = {
    vpc-cni = {
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    coredns    = {}
    kube-proxy = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      capacity_type  = "SPOT" # jusqu'à ~70% moins cher qu'à la demande ; acceptable pour du dev/démo non-critique
      min_size       = 1
      max_size       = 2
      desired_size   = 1

      labels = {
        role = "general"
      }
    }
  }

  tags = {
    Project = var.project_name
  }
}

# --- Registre d'images Docker (ECR) ---
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "IMMUTABLE" # une fois poussé, un tag ne peut plus être écrasé : traçabilité garantie

  # force_delete=true : acceptable ici car c'est un environnement de dev/démo
  # destiné à être détruit facilement. Sur un dépôt de production, on laisserait
  # cette valeur à false (défaut) pour qu'un `terraform destroy` accidentel ne
  # puisse pas supprimer silencieusement des images en production.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true # scan de vulnérabilités automatique à chaque push, sans étape CI supplémentaire
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Ne conserver que les 10 images les plus récentes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
