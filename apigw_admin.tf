// ---------------------------------------------------------------------------------------
// Admin HTTP API Gateway
// - HTTP API (v2) using a VPC Link to the internal ALB listener (HTTP)
// - JWT authorizer backed by Cognito User Pool
// - Single catch-all route to proxy to ALB; you can add fine-grained routes later
// ---------------------------------------------------------------------------------------

resource "aws_security_group" "apigw_vpclink" {
  name        = "${var.project_name}-${var.environment}-apigw-vpclink-sg"
  description = "ENIs for API Gateway VPC Link"
  vpc_id      = module.network.vpc_id

  // ALB listens on 80; VPC Link will connect to ALB
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  // Allow return traffic
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_apigatewayv2_vpc_link" "admin" {
  name               = "${var.project_name}-${var.environment}-admin-vpclink"
  security_group_ids = [aws_security_group.apigw_vpclink.id]
  subnet_ids         = module.network.private_subnets
}

resource "aws_apigatewayv2_api" "admin" {
  name          = "${var.project_name}-${var.environment}-admin"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "admin_jwt" {
  api_id = aws_apigatewayv2_api.admin.id
  name   = "cognito-jwt"
  authorizer_type = "JWT"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.this.id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
  }
}

resource "aws_apigatewayv2_integration" "admin_alb" {
  api_id                 = aws_apigatewayv2_api.admin.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  payload_format_version = "2.0"

  connection_type = "VPC_LINK"
  connection_id   = aws_apigatewayv2_vpc_link.admin.id

  // For HTTP APIs, ALB listener ARN is the integration URI
  integration_uri = aws_lb_listener.http.arn
}

resource "aws_apigatewayv2_route" "admin_any" {
  api_id    = aws_apigatewayv2_api.admin.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.admin_alb.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.admin_jwt.id
}

resource "aws_apigatewayv2_stage" "admin_prod" {
  api_id      = aws_apigatewayv2_api.admin.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_admin.arn
    format = jsonencode({
      requestId      = "$context.requestId",
      ip             = "$context.identity.sourceIp",
      requestTime    = "$context.requestTime",
      httpMethod     = "$context.httpMethod",
      path           = "$context.path",
      status         = "$context.status",
      protocol       = "$context.protocol",
      responseLength = "$context.responseLength"
    })
  }
}

resource "aws_cloudwatch_log_group" "api_admin" {
  name              = "/apigw/${var.project_name}/${var.environment}/admin"
  retention_in_days = 30
}

# ----------------------------
# Optional custom domain (Route53 + ACM in same region)
# ----------------------------

locals {
  admin_api_custom_domain_enabled = var.root_domain_name != null && var.admin_api_domain_name != null
}

data "aws_route53_zone" "root_apigw" {
  count = local.admin_api_custom_domain_enabled ? 1 : 0
  name  = var.root_domain_name
}

resource "aws_acm_certificate" "admin_api" {
  count             = local.admin_api_custom_domain_enabled ? 1 : 0
  domain_name       = var.admin_api_domain_name
  validation_method = "DNS"
}

resource "aws_route53_record" "admin_api_cert_validation" {
  count   = local.admin_api_custom_domain_enabled ? length(aws_acm_certificate.admin_api[0].domain_validation_options) : 0
  name    = aws_acm_certificate.admin_api[0].domain_validation_options[count.index].resource_record_name
  type    = aws_acm_certificate.admin_api[0].domain_validation_options[count.index].resource_record_type
  zone_id = data.aws_route53_zone.root_apigw[0].zone_id
  records = [aws_acm_certificate.admin_api[0].domain_validation_options[count.index].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "admin_api" {
  count                   = local.admin_api_custom_domain_enabled ? 1 : 0
  certificate_arn         = aws_acm_certificate.admin_api[0].arn
  validation_record_fqdns = [for r in aws_route53_record.admin_api_cert_validation : r.fqdn]
}

resource "aws_apigatewayv2_domain_name" "admin" {
  count = local.admin_api_custom_domain_enabled ? 1 : 0
  domain_name = var.admin_api_domain_name

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.admin_api[0].certificate_arn
    endpoint_type    = "REGIONAL"
    security_policy  = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "admin" {
  count       = local.admin_api_custom_domain_enabled ? 1 : 0
  api_id      = aws_apigatewayv2_api.admin.id
  domain_name = aws_apigatewayv2_domain_name.admin[0].id
  stage       = aws_apigatewayv2_stage.admin_prod.name
}

resource "aws_route53_record" "admin_api_alias" {
  count   = local.admin_api_custom_domain_enabled ? 1 : 0
  name    = var.admin_api_domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.root_apigw[0].zone_id

  alias {
    name                   = aws_apigatewayv2_domain_name.admin[0].domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.admin[0].domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}


