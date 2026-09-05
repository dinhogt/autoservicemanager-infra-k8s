resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name}-http"
  protocol_type = "HTTP"
  description   = "Fase 3 - auth CPF + proxy EKS (ADR-007)"

  cors_configuration {
    allow_headers = ["authorization", "content-type", "x-amzn-trace-id", "x-correlation-id"]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 300
  }

  tags = local.tags
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "jwt-cliente"

  jwt_configuration {
    audience = [var.jwt_audience]
    issuer   = local.jwt_issuer
  }

  depends_on = [time_sleep.jwks_propagation]
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      integrationErr = "$context.integrationErrorMessage"
    })
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${local.name}-http"
  retention_in_days = 14
  tags              = local.tags
}

data "aws_iam_policy_document" "apigw_logs" {
  statement {
    sid    = "APIGatewayLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.apigw.arn}:*"]
  }
}

resource "aws_cloudwatch_log_resource_policy" "apigw" {
  policy_name     = "${local.name}-apigw-logs"
  policy_document = data.aws_iam_policy_document.apigw_logs.json
}

# --- Lambda: POST /auth/cpf (público) ---
resource "aws_apigatewayv2_integration" "auth_cpf" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.auth_cpf.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

resource "aws_apigatewayv2_route" "auth_cpf" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /auth/cpf"
  target    = "integrations/${aws_apigatewayv2_integration.auth_cpf.id}"
}

resource "aws_lambda_permission" "apigw_auth" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_cpf.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*/auth/cpf"
}

# --- EKS via VPC Link + NLB ---
resource "aws_apigatewayv2_integration" "eks" {
  api_id               = aws_apigatewayv2_api.http.id
  integration_type     = "HTTP_PROXY"
  integration_uri      = aws_lb_listener.eks.arn
  integration_method   = "ANY"
  connection_type      = "VPC_LINK"
  connection_id        = aws_apigatewayv2_vpc_link.eks.id
  timeout_milliseconds = 30000

  request_parameters = {
    "overwrite:header.x-cpf"              = "$context.authorizer.claims.sub"
    "overwrite:header.x-scope"            = "$context.authorizer.claims.scope"
    "overwrite:header.x-gateway-verified" = "1"
  }
}

resource "aws_apigatewayv2_route" "clientes" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "ANY /clientes/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.eks.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "ordens" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "ANY /ordens-servico/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.eks.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "ordens_root" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "ANY /ordens-servico"
  target             = "integrations/${aws_apigatewayv2_integration.eks.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

# Admin / webhook: sem JWT RS256 — Nest valida HS256 / X-Webhook-Secret
resource "aws_apigatewayv2_route" "admin" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /admin/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.eks.id}"
}

resource "aws_apigatewayv2_route" "webhooks" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /webhooks/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.eks.id}"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.eks.id}"
}
