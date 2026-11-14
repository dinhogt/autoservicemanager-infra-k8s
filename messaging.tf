locals {
  phase4_service_names = toset(keys(var.phase4_services))
}

# Filas ponto a ponto para comandos destinados a cada serviço.
resource "aws_sqs_queue" "command_dlq" {
  for_each = local.phase4_service_names

  name                      = "${local.name}-${each.key}-commands-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds
  sqs_managed_sse_enabled   = true

  tags = merge(local.tags, {
    Service = each.key
    Purpose = "commands-dlq"
  })
}

resource "aws_sqs_queue" "command" {
  for_each = local.phase4_service_names

  name                       = "${local.name}-${each.key}-commands"
  message_retention_seconds  = var.queue_message_retention_seconds
  visibility_timeout_seconds = var.command_queue_visibility_timeout_seconds
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.command_dlq[each.key].arn
    maxReceiveCount     = var.command_queue_max_receive_count
  })

  tags = merge(local.tags, {
    Service = each.key
    Purpose = "commands"
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "command_dlq" {
  for_each = local.phase4_service_names

  queue_url = aws_sqs_queue.command_dlq[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.command[each.key].arn]
  })
}

# Cada serviço publica seus eventos; OS recebe todos em uma fila própria.
resource "aws_sns_topic" "service_events" {
  for_each = local.phase4_service_names

  name = "${local.name}-${each.key}-events"

  tags = merge(local.tags, {
    Service = each.key
    Purpose = "domain-events"
  })
}

resource "aws_sqs_queue" "os_events_dlq" {
  name                      = "${local.name}-os-events-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds
  sqs_managed_sse_enabled   = true

  tags = merge(local.tags, {
    Service = "os"
    Purpose = "events-dlq"
  })
}

resource "aws_sqs_queue" "os_events" {
  name                       = "${local.name}-os-events"
  message_retention_seconds  = var.queue_message_retention_seconds
  visibility_timeout_seconds = var.command_queue_visibility_timeout_seconds
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.os_events_dlq.arn
    maxReceiveCount     = var.command_queue_max_receive_count
  })

  tags = merge(local.tags, {
    Service = "os"
    Purpose = "domain-events"
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "os_events_dlq" {
  queue_url = aws_sqs_queue.os_events_dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.os_events.arn]
  })
}

data "aws_iam_policy_document" "os_events_queue" {
  statement {
    sid     = "AllowServiceTopics"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    resources = [aws_sqs_queue.os_events.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for topic in aws_sns_topic.service_events : topic.arn]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["sqs:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [aws_sqs_queue.os_events.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "os_events" {
  queue_url = aws_sqs_queue.os_events.id
  policy    = data.aws_iam_policy_document.os_events_queue.json
}

resource "aws_sns_topic_subscription" "os_events" {
  for_each = local.phase4_service_names

  topic_arn            = aws_sns_topic.service_events[each.key].arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.os_events.arn
  raw_message_delivery = true

  depends_on = [aws_sqs_queue_policy.os_events]
}
