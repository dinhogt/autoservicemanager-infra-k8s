# Notificações serverless — SNS → Lambda notify-os → SES (RFC-004)

resource "aws_sns_topic" "os_notifications" {
  name = "${local.name}-os-notifications"
  tags = local.tags
}

resource "aws_iam_role" "notify_lambda" {
  name = "${local.name}-notify-os"

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

resource "aws_iam_role_policy_attachment" "notify_lambda_basic" {
  role       = aws_iam_role.notify_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "notify_lambda_ses" {
  name = "${local.name}-notify-os-ses"
  role = aws_iam_role.notify_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = ["*"]
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

resource "aws_lambda_function" "notify_os" {
  function_name = "${local.name}-notify-os"
  role          = aws_iam_role.notify_lambda.arn
  handler       = "handler.handler"
  runtime       = "nodejs22.x"
  memory_size   = 128
  timeout       = 15
  filename      = data.archive_file.lambda_placeholder.output_path

  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      EMAIL_FROM = var.notify_email_from
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  depends_on = [
    aws_iam_role_policy_attachment.notify_lambda_basic,
    aws_iam_role_policy.notify_lambda_ses,
  ]
}

resource "aws_cloudwatch_log_group" "notify_os" {
  name              = "/aws/lambda/${aws_lambda_function.notify_os.function_name}"
  retention_in_days = 14
  tags              = local.tags
}

resource "aws_lambda_permission" "notify_os_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notify_os.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.os_notifications.arn
}

resource "aws_sns_topic_subscription" "notify_os" {
  topic_arn = aws_sns_topic.os_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.notify_os.arn
}
