variable "aws_region" {
  type        = string
  description = "Região AWS"
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Prefixo de nomes de recursos"
  default     = "autoservicemanager"
}

variable "environment" {
  type        = string
  description = "Ambiente (homolog|prod) — deve bater com a key do remote_state db/"
  default     = "homolog"
}

variable "tf_state_bucket" {
  type        = string
  description = "Bucket do state (mesmo do infra-db). CI resolve se vazio."
  default     = ""
}

variable "cluster_version" {
  type    = string
  default = "1.34"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type        = number
  description = "Homolog acadêmico: 1 node (FinOps). Subir para 2+ só se HPA/DaemonSets exigirem."
  default     = 1
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "jwt_kid" {
  type    = string
  default = "auth-cpf-1"
}

variable "jwt_audience" {
  type    = string
  default = "autoservicemanager-api"
}

variable "jwt_expires_in" {
  type    = string
  default = "3600"
}

variable "app_port" {
  type        = number
  description = "Porta do NestJS no target group / pods"
  default     = 3000
}

variable "lambda_memory_mb" {
  type    = number
  default = 512
}

variable "lambda_timeout_s" {
  type    = number
  default = 5
}

variable "notify_email_from" {
  type        = string
  description = "Remetente SES da Lambda notify-os (sandbox: e-mail verificado)"
  default     = "noreply@autoservicemanager.local"
}
