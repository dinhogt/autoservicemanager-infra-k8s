# NLB interno para VPC Link (API Gateway HTTP API → EKS)
resource "aws_security_group" "vpclink" {
  name        = "${local.name}-vpclink"
  description = "ENIs do VPC Link HTTP API"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-vpclink" })
}

resource "aws_security_group_rule" "nodes_from_vpclink" {
  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  security_group_id        = module.eks.node_security_group_id
  source_security_group_id = aws_security_group.vpclink.id
  description              = "App port from VPC Link ENIs"
}

resource "aws_security_group_rule" "nodes_from_nlb_health" {
  type              = "ingress"
  from_port         = var.app_port
  to_port           = var.app_port
  protocol          = "tcp"
  security_group_id = module.eks.node_security_group_id
  cidr_blocks       = [local.vpc_cidr]
  description       = "NLB health checks (VPC CIDR)"
}

resource "aws_lb" "eks" {
  name               = "${local.name}-nlb"
  load_balancer_type = "network"
  internal           = true
  subnets            = local.private_subnet_ids

  tags = local.tags
}

resource "aws_lb_target_group" "eks" {
  name        = "${local.name}-app"
  port        = var.app_port
  protocol    = "TCP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    port                = tostring(var.app_port)
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = local.tags
}

resource "aws_lb_listener" "eks" {
  load_balancer_arn = aws_lb.eks.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks.arn
  }
}

resource "aws_apigatewayv2_vpc_link" "eks" {
  name               = "${local.name}-vpclink"
  security_group_ids = [aws_security_group.vpclink.id]
  subnet_ids         = local.private_subnet_ids
  tags               = local.tags
}

locals {
  phase4_target_ports = setsubtract(
    toset([for config in values(var.phase4_services) : tostring(config.target_port)]),
    toset([tostring(var.app_port)])
  )
}

resource "aws_security_group_rule" "nodes_from_vpclink_phase4" {
  for_each = local.phase4_target_ports

  type                     = "ingress"
  from_port                = tonumber(each.value)
  to_port                  = tonumber(each.value)
  protocol                 = "tcp"
  security_group_id        = module.eks.node_security_group_id
  source_security_group_id = aws_security_group.vpclink.id
  description              = "Phase 4 service port from VPC Link ENIs"
}

resource "aws_security_group_rule" "nodes_from_nlb_health_phase4" {
  for_each = local.phase4_target_ports

  type              = "ingress"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  protocol          = "tcp"
  security_group_id = module.eks.node_security_group_id
  cidr_blocks       = [local.vpc_cidr]
  description       = "Phase 4 NLB health checks from VPC CIDR"
}

resource "aws_lb_target_group" "phase4_service" {
  for_each = var.phase4_services

  name        = substr("${local.name}-${each.key}", 0, 32)
  port        = each.value.target_port
  protocol    = "TCP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    port                = tostring(each.value.target_port)
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = merge(local.tags, { Service = each.key })
}

resource "aws_lb_listener" "phase4_service" {
  for_each = var.phase4_services

  load_balancer_arn = aws_lb.eks.arn
  port              = each.value.listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.phase4_service[each.key].arn
  }
}
