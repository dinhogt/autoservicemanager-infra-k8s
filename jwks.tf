# JWT RS256 — chave gerada no apply; privada no Secrets Manager; pública no JWKS
resource "tls_private_key" "jwt" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "${local.name}/jwt-auth-cpf"
  description             = "Chave privada JWT RS256 (Lambda authCpf)"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({
    privateKey = tls_private_key.jwt.private_key_pem
    kid        = var.jwt_kid
  })
}

data "external" "jwks" {
  program = ["node", "${path.module}/scripts/pem-to-jwks.mjs"]
  query = {
    privateKeyPem = tls_private_key.jwt.private_key_pem
    kid           = var.jwt_kid
  }
}

resource "aws_s3_bucket" "jwks" {
  bucket_prefix = "${local.name}-jwks-"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "jwks" {
  bucket = aws_s3_bucket.jwks.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "jwks" {
  bucket       = aws_s3_bucket.jwks.id
  key          = ".well-known/jwks.json"
  content      = data.external.jwks.result.jwks
  content_type = "application/json"
  etag         = md5(data.external.jwks.result.jwks)
}

resource "aws_s3_object" "openid_configuration" {
  bucket       = aws_s3_bucket.jwks.id
  key          = ".well-known/openid-configuration"
  content_type = "application/json"
  content = jsonencode({
    issuer   = "https://${aws_cloudfront_distribution.jwks.domain_name}"
    jwks_uri = "https://${aws_cloudfront_distribution.jwks.domain_name}/.well-known/jwks.json"
  })
  etag = md5(jsonencode({
    issuer   = "https://${aws_cloudfront_distribution.jwks.domain_name}"
    jwks_uri = "https://${aws_cloudfront_distribution.jwks.domain_name}/.well-known/jwks.json"
  }))
}

resource "aws_cloudfront_origin_access_control" "jwks" {
  name                              = "${local.name}-jwks-oac"
  description                       = "OAC JWKS S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "jwks" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name} JWKS"
  price_class     = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.jwks.bucket_regional_domain_name
    origin_id                = "jwks-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.jwks.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "jwks-s3"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 300
    max_ttl     = 3600
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.tags
}

data "aws_iam_policy_document" "jwks_oac" {
  statement {
    sid       = "AllowCloudFront"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.jwks.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.jwks.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "jwks" {
  bucket = aws_s3_bucket.jwks.id
  policy = data.aws_iam_policy_document.jwks_oac.json
}

locals {
  # API Gateway JWT Authorizer busca {issuer}/.well-known/openid-configuration
  jwt_issuer = "https://${aws_cloudfront_distribution.jwks.domain_name}"
}

resource "time_sleep" "jwks_propagation" {
  depends_on = [
    aws_s3_object.jwks,
    aws_s3_object.openid_configuration,
    aws_cloudfront_distribution.jwks,
  ]

  create_duration = "90s"
}
