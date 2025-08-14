// ---------------------------------------------------------------------------------------
// Useful outputs for composing layers
// - vpc_id and subnet IDs are consumed by compute and data layers (ECS, RDS)
// - ALB identifiers are useful for DNS/CloudFront or API Gateway private integrations
// ---------------------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.network.vpc_id
}

output "private_app_subnet_ids" {
  description = "Private application subnet IDs"
  value       = module.network.private_subnets
}

output "private_db_subnet_ids" {
  description = "Private database subnet IDs"
  value       = module.network.database_subnets
}

output "internal_alb_arn" {
  description = "ARN of the internal ALB"
  value       = aws_lb.internal_alb.arn
}

output "internal_alb_dns" {
  description = "DNS name of the internal ALB"
  value       = aws_lb.internal_alb.dns_name
}

// No NAT/IGW in private-only design

output "ecs_cluster_name" {
  value       = aws_ecs_cluster.this.name
  description = "ECS cluster name"
}

output "ecs_user_service_name" {
  value       = aws_ecs_service.user.name
  description = "User management ECS service name"
}

output "ecs_radio_service_name" {
  value       = aws_ecs_service.radio.name
  description = "Radio locator ECS service name"
}

output "rds_user_endpoint" {
  value       = aws_db_instance.user.address
  description = "RDS endpoint for user database"
}

output "rds_radio_endpoint" {
  value       = aws_db_instance.radio.address
  description = "RDS endpoint for radio database"
}

output "redis_primary_endpoint" {
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
  description = "Redis primary endpoint"
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.this.id
  description = "Cognito User Pool ID"
}

output "cognito_app_client_id" {
  value       = aws_cognito_user_pool_client.this.id
  description = "Cognito App Client ID"
}

output "cognito_domain" {
  value       = aws_cognito_user_pool_domain.this.domain
  description = "Cognito hosted UI domain"
}

output "admin_api_endpoint" {
  value       = aws_apigatewayv2_api.admin.api_endpoint
  description = "Admin HTTP API base URL"
}

output "client_api_endpoint" {
  value       = aws_apigatewayv2_api.client.api_endpoint
  description = "Client HTTP API base URL"
}

output "websocket_api_endpoint" {
  value       = aws_apigatewayv2_stage.ws_prod.invoke_url
  description = "WebSocket API URL"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.this.domain_name
  description = "CloudFront distribution domain"
}


