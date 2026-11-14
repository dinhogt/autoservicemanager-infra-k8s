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

variable "phase4_services" {
  description = "Portas e prefixos HTTP dos serviços extraídos na Fase 4."
  type = map(object({
    listener_port = number
    target_port   = number
    route_prefix  = string
  }))

  default = {
    billing = {
      listener_port = 8081
      target_port   = 3000
      route_prefix  = "billing"
    }
    execution = {
      listener_port = 8082
      target_port   = 3000
      route_prefix  = "execucoes"
    }
  }

  validation {
    condition = (
      length(var.phase4_services) == 2 &&
      alltrue([for service in ["billing", "execution"] : contains(keys(var.phase4_services), service)])
    )
    error_message = "phase4_services deve conter somente billing e execution; diagnóstico pertence ao Execution Service."
  }

  validation {
    condition = (
      length(distinct([for config in values(var.phase4_services) : config.listener_port])) == length(var.phase4_services) &&
      length(distinct([for config in values(var.phase4_services) : config.route_prefix])) == length(var.phase4_services) &&
      alltrue([
        for config in values(var.phase4_services) :
        config.listener_port >= 1 && config.listener_port <= 65535 &&
        config.target_port >= 1 && config.target_port <= 65535 &&
        can(regex("^[a-z0-9-]+$", config.route_prefix))
      ])
    )
    error_message = "listener_port e route_prefix devem ser únicos; portas devem ser válidas e prefixos devem usar a-z, 0-9 ou hífen."
  }
}

variable "command_queue_visibility_timeout_seconds" {
  type        = number
  description = "Visibility timeout das filas de comando; deve superar o timeout dos consumers."
  default     = 60
}

variable "command_queue_max_receive_count" {
  type        = number
  description = "Tentativas antes de mover uma mensagem de comando para a DLQ."
  default     = 5
}

variable "queue_message_retention_seconds" {
  type        = number
  description = "Retenção das filas principais em segundos."
  default     = 345600
}

variable "dlq_message_retention_seconds" {
  type        = number
  description = "Retenção das DLQs em segundos."
  default     = 1209600
}
