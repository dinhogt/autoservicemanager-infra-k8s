resource "aws_security_group" "lambda" {
  name        = "${local.name}-auth-lambda"
  description = "Lambda authCpf VPC to RDS"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-auth-lambda" })
}

resource "aws_iam_role" "lambda" {
  name = "${local.name}-auth-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_secrets" {
  name = "${local.name}-auth-lambda-secrets"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [
          local.db_secret_arn,
          aws_secretsmanager_secret.jwt.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
        ]
        Resource = ["*"]
      }
    ]
  })
}

data "archive_file" "lambda_placeholder" {
  type        = "zip"
  source_file = "${path.module}/placeholder/handler.js"
  output_path = "${path.module}/placeholder.zip"
}

resource "aws_lambda_function" "auth_cpf" {
  function_name = "${local.name}-auth-cpf"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.handler"
  runtime       = "nodejs22.x"
  memory_size   = var.lambda_memory_mb
  timeout       = var.lambda_timeout_s
  filename      = data.archive_file.lambda_placeholder.output_path

  # CI auth-lambda faz update-function-code; evita drift no apply
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      DB_SECRET_ARN       = local.db_secret_arn
      JWT_PRIVATE_KEY_ARN = aws_secretsmanager_secret.jwt.arn
      JWT_KID             = var.jwt_kid
      JWT_ISS             = local.jwt_issuer
      JWT_AUD             = var.jwt_audience
      JWT_EXPIRES_IN      = var.jwt_expires_in
    }
  }

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_iam_role_policy.lambda_secrets,
  ]
}

resource "aws_cloudwatch_log_group" "auth_cpf" {
  name              = "/aws/lambda/${aws_lambda_function.auth_cpf.function_name}"
  retention_in_days = 14
  tags              = local.tags
}
