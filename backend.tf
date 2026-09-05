# Backend remoto (ADR-008). Valores via `terraform init -backend-config=backend.hcl`
# Keys: k8s/homolog/terraform.tfstate | k8s/prod/terraform.tfstate

terraform {
  backend "s3" {
    # bucket         = "autoservicemanager-tfstate-<account-id>"
    # key            = "k8s/homolog/terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "autoservicemanager-tflock"
    # encrypt        = true
  }
}
