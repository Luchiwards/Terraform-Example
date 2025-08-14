// ---------------------------------------------------------------------------------------
// Client HTTP API Gateway
// - Reuses the existing VPC Link to the internal ALB
// - Cognito JWT authorizer (same user pool) – adjust scopes/policies per client needs
// ---------------------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "client" {
  name          = "${var.project_name}-${var.environment}-client"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "client_jwt" {
  api_id = aws_apigatewayv2_api.client.id
  name   = "cognito-jwt"
  authorizer_type = "JWT"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.this.id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
  }
}

resource "aws_apigatewayv2_integration" "client_alb" {
  api_id                 = aws_apigatewayv2_api.client.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  payload_format_version = "2.0"

  connection_type = "VPC_LINK"
  connection_id   = aws_apigatewayv2_vpc_link.admin.id

  integration_uri = aws_lb_listener.http.arn
}

resource "aws_apigatewayv2_route" "client_any" {
  api_id    = aws_apigatewayv2_api.client.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.client_alb.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.client_jwt.id
}

resource "aws_apigatewayv2_stage" "client_prod" {
  api_id      = aws_apigatewayv2_api.client.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_client.arn
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

resource "aws_cloudwatch_log_group" "api_client" {
  name              = "/apigw/${var.project_name}/${var.environment}/client"
  retention_in_days = 30
}

locals {
  client_api_custom_domain_enabled = var.root_domain_name != null && var.client_api_domain_name != null
}

data "aws_route53_zone" "root_apigw_client" {
  count = local.client_api_custom_domain_enabled ? 1 : 0
  name  = var.root_domain_name
}

resource "aws_acm_certificate" "client_api" {
  count             = local.client_api_custom_domain_enabled ? 1 : 0
  domain_name       = var.client_api_domain_name
  validation_method = "DNS"
}

resource "aws_route53_record" "client_api_cert_validation" {
  count   = local.client_api_custom_domain_enabled ? length(aws_acm_certificate.client_api[0].domain_validation_options) : 0
  name    = aws_acm_certificate.client_api[0].domain_validation_options[count.index].resource_record_name
  type    = aws_acm_certificate.client_api[0].domain_validation_options[count.index].resource_record_type
  zone_id = data.aws_route53_zone.root_apigw_client[0].zone_id
  records = [aws_acm_certificate.client_api[0].domain_validation_options[count.index].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "client_api" {
  count                   = local.client_api_custom_domain_enabled ? 1 : 0
  certificate_arn         = aws_acm_certificate.client_api[0].arn
  validation_record_fqdns = [for r in aws_route53_record.client_api_cert_validation : r.fqdn]
}

resource "aws_apigatewayv2_domain_name" "client" {
  count = local.client_api_custom_domain_enabled ? 1 : 0
  domain_name = var.client_api_domain_name

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.client_api[0].certificate_arn
    endpoint_type    = "REGIONAL"
    security_policy  = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "client" {
  count       = local.client_api_custom_domain_enabled ? 1 : 0
  api_id      = aws_apigatewayv2_api.client.id
  domain_name = aws_apigatewayv2_domain_name.client[0].id
  stage       = aws_apigatewayv2_stage.client_prod.name
}

resource "aws_route53_record" "client_api_alias" {
  count   = local.client_api_custom_domain_enabled ? 1 : 0
  name    = var.client_api_domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.root_apigw_client[0].zone_id

  alias {
    name                   = aws_apigatewayv2_domain_name.client[0].domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.client[0].domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}


