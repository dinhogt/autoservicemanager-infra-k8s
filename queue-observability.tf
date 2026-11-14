# Base mínima; dashboards e SLOs detalhados das filas ficam para entrega posterior.
resource "aws_cloudwatch_metric_alarm" "command_dlq_messages" {
  for_each = local.phase4_service_names

  alarm_name          = "${local.name}-${each.key}-commands-dlq-not-empty"
  alarm_description   = "A DLQ de comandos de ${each.key} possui mensagens."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.command_dlq[each.key].name
  }

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]
  tags          = merge(local.tags, { Service = each.key })
}

resource "aws_cloudwatch_metric_alarm" "command_oldest_message" {
  for_each = local.phase4_service_names

  alarm_name          = "${local.name}-${each.key}-commands-age"
  alarm_description   = "Mensagem de comando de ${each.key} aguardando acima do limite."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 300
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.command[each.key].name
  }

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]
  tags          = merge(local.tags, { Service = each.key })
}

resource "aws_cloudwatch_metric_alarm" "os_events_dlq_messages" {
  alarm_name          = "${local.name}-os-events-dlq-not-empty"
  alarm_description   = "A DLQ de eventos consumidos por OS possui mensagens."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.os_events_dlq.name
  }

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]
  tags          = merge(local.tags, { Service = "os" })
}

resource "aws_cloudwatch_metric_alarm" "os_events_oldest_message" {
  alarm_name          = "${local.name}-os-events-age"
  alarm_description   = "Evento da Saga aguardando consumo por mais de cinco minutos."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 300
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.os_events.name
  }

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]
  tags          = merge(local.tags, { Service = "os" })
}
