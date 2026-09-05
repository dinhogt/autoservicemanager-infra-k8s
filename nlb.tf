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
