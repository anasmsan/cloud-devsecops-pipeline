# État distant : stocké dans le bucket S3 créé par terraform/bootstrap, verrouillé
# via la table DynamoDB correspondante. Toute l'équipe (ou, ici, tout poste sur
# lequel ce projet est cloné) partage ainsi le même état, avec verrouillage
# empêchant deux applys simultanés de se marcher dessus.
#
# Les valeurs exactes (bucket/table) sont injectées via `terraform init
# -backend-config=backend.hcl` plutôt qu'en dur ici, car le nom du bucket
# S3 doit être unique dans le monde entier et dépend donc de qui déploie.
terraform {
  backend "s3" {
    key     = "dev/terraform.tfstate"
    region  = "eu-west-3"
    encrypt = true
  }
}
