locals {
  name = "${var.project_name}-${var.environment}"
  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Stack       = "infra-k8s"
  }

  # Conta resolvida no plan; bucket pode vir de var ou convenção ADR-008
  state_bucket = var.tf_state_bucket != "" ? var.tf_state_bucket : "autoservicemanager-tfstate-${data.aws_caller_identity.current.account_id}"
  db_state_key = "db/${var.environment}/terraform.tfstate"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Contrato ADR-008 — outputs do stack infra-db
data "terraform_remote_state" "db" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = local.db_state_key
    region = var.aws_region
  }
}

locals {
  vpc_id             = data.terraform_remote_state.db.outputs.vpc_id
  vpc_cidr           = data.terraform_remote_state.db.outputs.vpc_cidr
  private_subnet_ids = data.terraform_remote_state.db.outputs.private_subnet_ids
  public_subnet_ids  = data.terraform_remote_state.db.outputs.public_subnet_ids
  db_sg_id           = data.terraform_remote_state.db.outputs.db_sg_id
  db_port            = data.terraform_remote_state.db.outputs.db_port
  db_secret_arn      = data.terraform_remote_state.db.outputs.db_secret_arn
}

module "eks" {
  source = "./modules/eks"

  name            = local.name
  vpc_id          = local.vpc_id
  subnet_ids      = local.private_subnet_ids
  cluster_version = var.cluster_version
  instance_types  = var.node_instance_types
  desired_size    = var.node_desired_size
  min_size        = var.node_min_size
  max_size        = var.node_max_size
  tags            = local.tags
}

# MySQL: somente SG→SG (hardening infra-db)
resource "aws_security_group_rule" "rds_from_eks_nodes" {
  type                     = "ingress"
  from_port                = local.db_port
  to_port                  = local.db_port
  protocol                 = "tcp"
  security_group_id        = local.db_sg_id
  source_security_group_id = module.eks.node_security_group_id
  description              = "MySQL from EKS nodes"
}

resource "aws_security_group_rule" "rds_from_lambda" {
  type                     = "ingress"
  from_port                = local.db_port
  to_port                  = local.db_port
  protocol                 = "tcp"
  security_group_id        = local.db_sg_id
  source_security_group_id = aws_security_group.lambda.id
  description              = "MySQL from auth Lambda"
}
