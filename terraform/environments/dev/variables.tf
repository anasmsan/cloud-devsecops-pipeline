variable "aws_region" {
  description = "Région AWS de déploiement"
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Nom du projet, utilisé comme préfixe pour nommer les ressources"
  type        = string
  default     = "devsecops-demo"
}

variable "cluster_version" {
  description = "Version de Kubernetes pour le control plane EKS"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "Plage d'adresses IP du VPC"
  type        = string
  default     = "10.42.0.0/16"
}

variable "node_instance_type" {
  description = "Type d'instance EC2 pour le node group (volontairement petit et en Spot pour un environnement de démo/dev, jamais utilisé tel quel pour une charge de production critique)"
  type        = string
  default     = "t3.small"
}

variable "admin_cidr_blocks" {
  description = <<-EOT
    Plages IP autorisées à atteindre l'API Kubernetes publique du cluster
    (typiquement : l'IP de la personne qui administre le cluster). Ne JAMAIS
    laisser à 0.0.0.0/0 : ce serait exposer l'API du cluster à Internet entier.
  EOT
  type        = list(string)
}
