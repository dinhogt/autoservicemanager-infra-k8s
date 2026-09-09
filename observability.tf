# Observabilidade Fase 3 — Container Insights + Fluent Bit (addon), dashboards e alarmes.
# X-Ray DaemonSet vive em k8s/xray-daemonset.yaml (apply com o app).

resource "aws_iam_role_policy_attachment" "node_cloudwatch_agent" {
  role       = module.eks.node_role_name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "node_xray" {
  role       = module.eks.node_role_name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_iam_role_policy_attachment.node_cloudwatch_agent,
    aws_iam_role_policy_attachment.node_xray,
  ]

  tags = local.tags
}

# Log groups usados pelo Fluent Bit / Container Insights (pré-criados para filters/retention)
resource "aws_cloudwatch_log_group" "eks_application" {
  name              = "/aws/containerinsights/${module.eks.cluster_name}/application"
  retention_in_days = 14
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "eks_performance" {
  name              = "/aws/containerinsights/${module.eks.cluster_name}/performance"
  retention_in_days = 14
  tags              = local.tags
}

resource "aws_sns_topic" "ops_alerts" {
  name = "${local.name}-ops-alerts"
  tags = local.tags
}

# Metric filter: falhas de transição de OS (JSON logger com event=os_transicao_erro)
resource "aws_cloudwatch_log_metric_filter" "os_transicao_erro" {
  name           = "${local.name}-os-transicao-erro"
  log_group_name = aws_cloudwatch_log_group.eks_application.name
  pattern        = "{ $.event = \"os_transicao_erro\" }"

  metric_transformation {
    name      = "OsTransicaoErro"
    namespace = "AutoServiceManager/${var.environment}"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_dashboard" "fase3" {
  dashboard_name = "${local.name}-ops"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# AutoServiceManager (${var.environment}) — API Gateway · Lambda auth · EKS · OS"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "APIGW — volume (Count)"
          region = var.aws_region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.http.id, { label = "requests" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "APIGW — latência p95 / p99"
          region = var.aws_region
          period = 60
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.http.id, { stat = "p95", label = "p95" }],
            ["...", { stat = "p99", label = "p99" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "APIGW — 4xx / 5xx"
          region = var.aws_region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApiGateway", "4xx", "ApiId", aws_apigatewayv2_api.http.id, { label = "4xx" }],
            [".", "5xx", ".", ".", { label = "5xx" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "Lambda authCpf — duração / erros"
          region = var.aws_region
          period = 60
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.auth_cpf.function_name, { stat = "p95", label = "p95 ms" }],
            [".", "Errors", ".", ".", { stat = "Sum", label = "errors", yAxis = "right" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "NLB — healthy / unhealthy hosts"
          region = var.aws_region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/NetworkELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.eks.arn_suffix, "LoadBalancer", aws_lb.eks.arn_suffix, { label = "healthy" }],
            [".", "UnHealthyHostCount", ".", ".", ".", ".", { label = "unhealthy" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "OS — falhas de transição"
          region = var.aws_region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AutoServiceManager/${var.environment}", "OsTransicaoErro", { label = "os_transicao_erro" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 8
        height = 6
        properties = {
          title  = "OS criadas — volume diário"
          region = var.aws_region
          stat   = "Sum"
          period = 86400
          metrics = [
            ["AutoServiceManager/${var.environment}", "OsCriada", { label = "OsCriada" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 13
        width  = 8
        height = 6
        properties = {
          title  = "Tempo médio por fase (ms)"
          region = var.aws_region
          period = 300
          metrics = [
            ["AutoServiceManager/${var.environment}", "OsFaseDuracao", "Fase", "Diagnostico", { stat = "Average", label = "Diagnóstico" }],
            ["...", "Execucao", { stat = "Average", label = "Execução" }],
            ["...", "Finalizacao", { stat = "Average", label = "Finalização" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 13
        width  = 8
        height = 6
        properties = {
          title  = "EKS — CPU / memória pods (Container Insights)"
          region = var.aws_region
          period = 60
          metrics = [
            ["ContainerInsights", "pod_cpu_utilization", "ClusterName", module.eks.cluster_name, "Namespace", "autoservice", { stat = "Average", label = "CPU %" }],
            [".", "pod_memory_utilization", ".", ".", ".", ".", { stat = "Average", label = "Mem %", yAxis = "right" }],
          ]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 19
        width  = 24
        height = 6
        properties = {
          title  = "Logs Insights — erros app (correlationId / xrayTraceId)"
          region = var.aws_region
          query  = <<-EOT
            SOURCE '${aws_cloudwatch_log_group.eks_application.name}'
            | fields @timestamp, correlationId, xrayTraceId, context, message
            | filter level = "error"
            | sort @timestamp desc
            | limit 40
          EOT
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "apigw_latency_p95" {
  alarm_name          = "${local.name}-apigw-p95-gt-1s"
  alarm_description   = "API Gateway p95 > 1s — ver docs/observability/alerts.md"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 1000
  treat_missing_data  = "notBreaching"

  metric_query {
    id = "p95"
    metric {
      metric_name = "Latency"
      namespace   = "AWS/ApiGateway"
      period      = 60
      stat        = "p95"
      dimensions = {
        ApiId = aws_apigatewayv2_api.http.id
      }
    }
    return_data = true
  }

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "apigw_5xx_rate" {
  alarm_name          = "${local.name}-apigw-5xx-gt-1pct"
  alarm_description   = "Taxa 5xx API Gateway > 1% — ver docs/observability/alerts.md"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "e5"
    return_data = false
    metric {
      metric_name = "5xx"
      namespace   = "AWS/ApiGateway"
      period      = 60
      stat        = "Sum"
      dimensions = {
        ApiId = aws_apigatewayv2_api.http.id
      }
    }
  }

  metric_query {
    id          = "cnt"
    return_data = false
    metric {
      metric_name = "Count"
      namespace   = "AWS/ApiGateway"
      period      = 60
      stat        = "Sum"
      dimensions = {
        ApiId = aws_apigatewayv2_api.http.id
      }
    }
  }

  metric_query {
    id          = "rate"
    expression  = "IF(cnt>0, 100*(e5/cnt), 0)"
    label       = "5xx_pct"
    return_data = true
  }

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "nlb_unhealthy" {
  alarm_name          = "${local.name}-nlb-unhealthy-hosts"
  alarm_description   = "NLB com hosts unhealthy (health < 100%) — ver docs/observability/alerts.md"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.eks.arn_suffix
    LoadBalancer = aws_lb.eks.arn_suffix
  }

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_auth_errors" {
  alarm_name          = "${local.name}-auth-cpf-errors"
  alarm_description   = "Lambda authCpf com erros — ver docs/observability/alerts.md"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.auth_cpf.function_name
  }

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "os_transicao_erro" {
  alarm_name          = "${local.name}-os-transicao-erro"
  alarm_description   = "Falhas de transição de OS (metric filter) — ver docs/observability/alerts.md"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "OsTransicaoErro"
  namespace           = "AutoServiceManager/${var.environment}"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]
  tags          = local.tags
}
