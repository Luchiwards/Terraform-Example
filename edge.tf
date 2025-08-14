// ---------------------------------------------------------------------------------------
// Route53 and CloudFront (optional custom domain). CloudFront will front the Admin API
// by default; you can attach additional origins later (Client API, static sites, etc.).
// ---------------------------------------------------------------------------------------

locals {
  use_custom_domain = var.root_domain_name != null && var.cloudfront_domain != null
}

data "aws_route53_zone" "root" {
  count = local.use_custom_domain ? 1 : 0
  name  = var.root_domain_name
}

resource "aws_acm_certificate" "cf" {
  count             = local.use_custom_domain ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = var.cloudfront_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cf_validation" {
  count   = local.use_custom_domain ? length(aws_acm_certificate.cf[0].domain_validation_options) : 0
  name    = aws_acm_certificate.cf[0].domain_validation_options[count.index].resource_record_name
  type    = aws_acm_certificate.cf[0].domain_validation_options[count.index].resource_record_type
  zone_id = data.aws_route53_zone.root[0].zone_id
  records = [aws_acm_certificate.cf[0].domain_validation_options[count.index].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cf" {
  count                   = local.use_custom_domain ? 1 : 0
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cf[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cf_validation : r.fqdn]
}

resource "aws_cloudfront_origin_access_control" "oac" {
  // Placeholder in case we add S3 origins later; not used for API Gateway
  name                              = "${var.project_name}-${var.environment}-oac"
  description                       = "Default OAC"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "never"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled = true

  origin {
    domain_name = replace(aws_apigatewayv2_api.admin.api_endpoint, "https://", "")
    origin_id   = "admin-api"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "admin-api"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]

    forwarded_values {
      query_string = true
      headers      = ["Authorization"]
      cookies {
        forward = "all"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = !local.use_custom_domain
    acm_certificate_arn            = local.use_custom_domain ? aws_acm_certificate_validation.cf[0].certificate_arn : null
    ssl_support_method             = local.use_custom_domain ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  price_class = "PriceClass_100"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_route53_record" "cf_alias" {
  count   = local.use_custom_domain ? 1 : 0
  name    = var.cloudfront_domain
  type    = "A"
  zone_id = data.aws_route53_zone.root[0].zone_id

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}


