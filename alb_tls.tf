// ---------------------------------------------------------------------------------------
// Internal ALB TLS (HTTPS listener on 443) with ACM cert in the same region.
// Optional: only created if internal_alb_domain_name and root_domain_name are set.
// ---------------------------------------------------------------------------------------

locals {
  enable_internal_alb_tls = var.root_domain_name != null && var.internal_alb_domain_name != null
}

data "aws_route53_zone" "internal_alb" {
  count = local.enable_internal_alb_tls ? 1 : 0
  name  = var.root_domain_name
}

resource "aws_acm_certificate" "internal_alb" {
  count             = local.enable_internal_alb_tls ? 1 : 0
  domain_name       = var.internal_alb_domain_name
  validation_method = "DNS"
}

resource "aws_route53_record" "internal_alb_cert_validation" {
  count   = local.enable_internal_alb_tls ? length(aws_acm_certificate.internal_alb[0].domain_validation_options) : 0
  name    = aws_acm_certificate.internal_alb[0].domain_validation_options[count.index].resource_record_name
  type    = aws_acm_certificate.internal_alb[0].domain_validation_options[count.index].resource_record_type
  zone_id = data.aws_route53_zone.internal_alb[0].zone_id
  records = [aws_acm_certificate.internal_alb[0].domain_validation_options[count.index].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "internal_alb" {
  count                   = local.enable_internal_alb_tls ? 1 : 0
  certificate_arn         = aws_acm_certificate.internal_alb[0].arn
  validation_record_fqdns = [for r in aws_route53_record.internal_alb_cert_validation : r.fqdn]
}

resource "aws_lb_listener" "https" {
  count             = local.enable_internal_alb_tls ? 1 : 0
  load_balancer_arn = aws_lb.internal_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.internal_alb[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_user_mgmt.arn
  }
}


