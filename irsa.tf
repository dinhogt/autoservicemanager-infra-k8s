# IRSA — ServiceAccount autoservice/autoservice-api lê Secrets Manager + X-Ray
data "aws_iam_policy_document" "app_irsa_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:autoservice:autoservice-api"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_irsa" {
  name               = "${local.name}-app-irsa"
  assume_role_policy = data.aws_iam_policy_document.app_irsa_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "app_irsa" {
  name = "${local.name}-app-runtime"
  role = aws_iam_role.app_irsa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadDbSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [local.db_secret_arn]
      },
      {
        Sid      = "XRay"
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
        Resource = ["*"]
      },
      {
        Sid      = "PublishOsNotifications"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.os_notifications.arn]
      },
      {
        Sid      = "SendServiceCommands"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:GetQueueUrl"]
        Resource = [for queue in aws_sqs_queue.command : queue.arn]
      },
      {
        Sid    = "ConsumeServiceEvents"
        Effect = "Allow"
        Action = [
          "sqs:ChangeMessageVisibility",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
        ]
        Resource = [aws_sqs_queue.os_events.arn]
      }
    ]
  })
}

# IRSA migrate Job
data "aws_iam_policy_document" "migrate_irsa_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:autoservice:autoservice-migrate"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "migrate_irsa" {
  name               = "${local.name}-migrate-irsa"
  assume_role_policy = data.aws_iam_policy_document.migrate_irsa_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "migrate_irsa" {
  name = "${local.name}-migrate-secrets"
  role = aws_iam_role.migrate_irsa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = [local.db_secret_arn]
    }]
  })
}

# IRSA mínimo por serviço da Fase 4: consome sua command queue, publica seu
# tópico e acessa somente sua tabela quando o serviço possui persistência.
data "aws_iam_policy_document" "phase4_service_assume" {
  for_each = local.phase4_service_names

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:autoservice:autoservice-${each.key}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "phase4_service" {
  for_each = local.phase4_service_names

  name               = "${local.name}-${each.key}-irsa"
  assume_role_policy = data.aws_iam_policy_document.phase4_service_assume[each.key].json
  tags               = merge(local.tags, { Service = each.key })
}

resource "aws_iam_role_policy" "phase4_service" {
  for_each = local.phase4_service_names

  name = "${local.name}-${each.key}-runtime"
  role = aws_iam_role.phase4_service[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "ConsumeCommands"
          Effect = "Allow"
          Action = [
            "sqs:ChangeMessageVisibility",
            "sqs:DeleteMessage",
            "sqs:GetQueueAttributes",
            "sqs:GetQueueUrl",
            "sqs:ReceiveMessage",
          ]
          Resource = [aws_sqs_queue.command[each.key].arn]
        },
        {
          Sid      = "PublishDomainEvents"
          Effect   = "Allow"
          Action   = ["sns:Publish"]
          Resource = [aws_sns_topic.service_events[each.key].arn]
        },
        {
          Sid      = "WriteTraces"
          Effect   = "Allow"
          Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
          Resource = ["*"]
        }
      ],
      contains(keys(local.dynamodb_table_arns), each.key) ? [
        {
          Sid    = "ServiceTable"
          Effect = "Allow"
          Action = [
            "dynamodb:BatchGetItem",
            "dynamodb:BatchWriteItem",
            "dynamodb:ConditionCheckItem",
            "dynamodb:DeleteItem",
            "dynamodb:DescribeTable",
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:Query",
            "dynamodb:Scan",
            "dynamodb:UpdateItem",
          ]
          Resource = [
            local.dynamodb_table_arns[each.key],
            "${local.dynamodb_table_arns[each.key]}/index/*",
          ]
        }
      ] : []
    )
  })
}
