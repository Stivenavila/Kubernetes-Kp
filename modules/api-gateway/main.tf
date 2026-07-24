## -----------------------------------------------------
## NLB interno (target para VPC Link)
## -----------------------------------------------------

resource "aws_lb" "internal" {
  name               = "${var.name_prefix}-internal-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.private_subnet_ids

  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.name_prefix}-internal-nlb"
  }
}

resource "aws_lb_target_group" "k8s_ingress" {
  name        = "${var.name_prefix}-k8s-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Name = "${var.name_prefix}-k8s-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_ingress.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_ingress.arn
  }
}

## -----------------------------------------------------
## VPC Link
## -----------------------------------------------------

resource "aws_api_gateway_vpc_link" "this" {
  name        = "${var.name_prefix}-vpc-link"
  target_arns = [aws_lb.internal.arn]

  tags = {
    Name = "${var.name_prefix}-vpc-link"
  }
}

## -----------------------------------------------------
## REST API
## -----------------------------------------------------

resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.name_prefix}-api"
  description = "REST API Gateway for EKS workloads - ${var.name_prefix}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.name_prefix}-api"
  }
}

## -----------------------------------------------------
## Proxy Resource ({proxy+}) — catch-all to backend
## -----------------------------------------------------

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method

  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${aws_lb.internal.dns_name}/{proxy}"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.this.id

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }

  timeout_milliseconds = 29000
}

## Root resource method (/)
resource "aws_api_gateway_method" "root" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_rest_api.this.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_rest_api.this.root_resource_id
  http_method = aws_api_gateway_method.root.http_method

  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${aws_lb.internal.dns_name}/"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.this.id

  timeout_milliseconds = 29000
}

## -----------------------------------------------------
## Deployment & Stage
## -----------------------------------------------------

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.proxy.id,
      aws_api_gateway_method.root.id,
      aws_api_gateway_integration.root.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.proxy,
    aws_api_gateway_integration.root,
  ]
}

resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name = "${var.name_prefix}-api-stage-${var.stage_name}"
  }
}

## -----------------------------------------------------
## CloudWatch Logs for API Gateway
## -----------------------------------------------------

resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${var.name_prefix}-api"
  retention_in_days = 30

  tags = {
    Name = "${var.name_prefix}-apigw-logs"
  }
}

## -----------------------------------------------------
## WAF WebACL Association (best practice for REST API)
## -----------------------------------------------------

resource "aws_wafv2_web_acl" "api" {
  name        = "${var.name_prefix}-api-waf"
  description = "WAF for API Gateway - rate limiting and common rules"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-rate-limit"
    }
  }

  rule {
    name     = "aws-managed-common-rules"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-common-rules"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-waf"
  }

  tags = {
    Name = "${var.name_prefix}-api-waf"
  }
}

resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_api_gateway_stage.this.arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}
