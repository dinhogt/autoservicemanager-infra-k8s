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
