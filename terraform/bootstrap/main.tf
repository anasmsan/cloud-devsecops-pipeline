# Ce module "bootstrap" crée l'infrastructure nécessaire pour stocker l'état
# Terraform (terraform.tfstate) du reste du projet de façon partagée et
# verrouillée : un bucket S3 (versionné et chiffré) pour le fichier d'état,
# et une table DynamoDB pour verrouiller l'état pendant un apply (empêche
# deux `terraform apply` concurrents de corrompre l'état).
#
# On applique CE module en premier, une seule fois, avec un état local
# (il n'y a pas de "backend distant" pour stocker l'état... de l'état !).
# C'est un cas particulier volontaire, documenté dans le rapport explicatif.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_kms_key" "terraform_state" {
  description             = "Clé KMS dédiée au chiffrement de l'état Terraform (S3) et du verrou (DynamoDB)"
  deletion_window_in_days = 7
  enable_key_rotation     = true # rotation automatique annuelle de la clé, sans changer son identifiant

  tags = {
    Project   = "cloud-devsecops-pipeline"
    ManagedBy = "terraform-bootstrap"
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/${var.project_prefix}-tfstate"
  target_key_id = aws_kms_key.terraform_state.key_id
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  # Empêche une suppression accidentelle du bucket qui contient l'état de
  # TOUTE l'infrastructure du projet.
  lifecycle {
    prevent_destroy = false # mis à false pour permettre la démo de destruction complète en fin de test
  }

  tags = {
    Project   = "cloud-devsecops-pipeline"
    ManagedBy = "terraform-bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled" # permet de retrouver une version antérieure de l'état en cas d'erreur
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true # réduit le coût des appels KMS pour chaque objet
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST" # facturé à l'usage réel, pas de coût fixe pour une table quasi-vide
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state.arn
  }

  point_in_time_recovery {
    enabled = true # permet de restaurer la table à un instant T en cas d'écriture accidentelle/malveillante
  }

  tags = {
    Project   = "cloud-devsecops-pipeline"
    ManagedBy = "terraform-bootstrap"
  }
}
