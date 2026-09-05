output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_node_security_group_id" {
  value = module.eks.node_security_group_id
}

output "eks_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "app_irsa_role_arn" {
  description = "Anotar no ServiceAccount autoservice/autoservice-api"
  value       = aws_iam_role.app_irsa.arn
}

output "migrate_irsa_role_arn" {
  description = "Anotar no ServiceAccount autoservice/autoservice-migrate"
  value       = aws_iam_role.migrate_irsa.arn
}

output "nlb_arn" {
  value = aws_lb.eks.arn
}

output "nlb_dns_name" {
  value = aws_lb.eks.dns_name
}

output "target_group_arn" {
  description = "Registrar IPs dos pods (AWS LB Controller TargetGroupBinding) ou anotação do Service"
  value       = aws_lb_target_group.eks.arn
}

output "vpc_link_id" {
  value = aws_apigatewayv2_vpc_link.eks.id
}

output "api_endpoint" {
  description = "URL base do API Gateway HTTP API"
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "jwt_issuer" {
  description = "Issuer HTTPS (JWKS em {issuer}/.well-known/jwks.json)"
  value       = local.jwt_issuer
}

output "jwt_audience" {
  value = var.jwt_audience
}

output "jwt_secret_arn" {
  value     = aws_secretsmanager_secret.jwt.arn
  sensitive = true
}

output "auth_lambda_name" {
  value = aws_lambda_function.auth_cpf.function_name
}

output "auth_lambda_arn" {
  value = aws_lambda_function.auth_cpf.arn
}

output "db_secret_arn" {
  value     = local.db_secret_arn
  sensitive = true
}

output "jwks_bucket" {
  value = aws_s3_bucket.jwks.id
}

output "ops_alerts_topic_arn" {
  description = "SNS para alarmes CloudWatch (assinar e-mail/ChatOps)"
  value       = aws_sns_topic.ops_alerts.arn
}

output "ops_dashboard_name" {
  value = aws_cloudwatch_dashboard.fase3.dashboard_name
}

output "cloudwatch_application_log_group" {
  value = aws_cloudwatch_log_group.eks_application.name
}
