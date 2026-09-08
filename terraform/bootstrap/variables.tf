variable "aws_region" {
  description = "Région AWS où créer les ressources de bootstrap"
  type        = string
  default     = "eu-west-3"
}

variable "state_bucket_name" {
  description = "Nom du bucket S3 qui stockera le fichier d'état Terraform (doit être globalement unique sur tout AWS)"
  type        = string
}

variable "project_prefix" {
  description = "Préfixe court utilisé pour nommer les ressources (alias KMS, etc.)"
  type        = string
  default     = "devsecops-demo"
}

variable "lock_table_name" {
  description = "Nom de la table DynamoDB utilisée pour verrouiller l'état Terraform"
  type        = string
  default     = "cloud-devsecops-pipeline-tf-locks"
}
