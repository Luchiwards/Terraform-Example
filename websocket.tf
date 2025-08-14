// ---------------------------------------------------------------------------------------
// WebSocket API, SQS queues, and Lambda consumers
// - WebSocket API routes ($connect/$disconnect/$default) → websocket_transform Lambda
// - SQS queues for async events, with DLQs
// - emergency_button Lambda triggered by SQS
// ---------------------------------------------------------------------------------------

resource "aws_sqs_queue" "events_dlq" {
  name = "${var.project_name}-${var.environment}-events-dlq"
}

resource "aws_sqs_queue" "events" {
  name                      = "${var.project_name}-${var.environment}-events"
  message_retention_seconds = 1209600
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn,
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "emergency_dlq" {
  name = "${var.project_name}-${var.environment}-emergency-dlq"
}

resource "aws_sqs_queue" "emergency" {
  name                      = "${var.project_name}-${var.environment}-emergency"
  message_retention_seconds = 1209600
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.emergency_dlq.arn,
    maxReceiveCount     = 5
  })
}

// ----------------------------
// Lambda IAM
// ----------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-${var.environment}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_sqs_policy" {
  name = "${var.project_name}-${var.environment}-lambda-sqs"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"],
        Resource = [aws_sqs_queue.events.arn, aws_sqs_queue.emergency.arn, aws_sqs_queue.events_dlq.arn, aws_sqs_queue.emergency_dlq.arn]
      }
    ]
  })
}

// ----------------------------
// Lambda code (inline minimal handlers)
// ----------------------------

locals {
  websocket_transform_code = <<EOT
import json

def handler(event, context):
    # Echo back message or perform transformation
    return {
        "statusCode": 200,
        "body": json.dumps({"ok": True, "event": event.get("requestContext", {}).get("routeKey", "default")})
    }
EOT

  emergency_button_code = <<EOT
import json

def handler(event, context):
    # Process SQS messages (emergency)
    for record in event.get("Records", []):
        _body = record.get("body")
    return {"statusCode": 200}
EOT
}

resource "local_file" "websocket_transform_py" {
  filename = "lambda/websocket_transform.py"
  content  = local.websocket_transform_code
}

resource "local_file" "emergency_button_py" {
  filename = "lambda/emergency_button.py"
  content  = local.emergency_button_code
}

resource "archive_file" "websocket_transform_zip" {
  type        = "zip"
  source_file = local_file.websocket_transform_py.filename
  output_path = "lambda/websocket_transform.zip"
}

resource "archive_file" "emergency_button_zip" {
  type        = "zip"
  source_file = local_file.emergency_button_py.filename
  output_path = "lambda/emergency_button.zip"
}

resource "aws_lambda_function" "websocket_transform" {
  function_name    = "${var.project_name}-${var.environment}-websocket-transform"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "websocket_transform.handler"
  runtime          = var.lambda_runtime
  filename         = archive_file.websocket_transform_zip.output_path
  source_code_hash = archive_file.websocket_transform_zip.output_base64sha256
}

resource "aws_lambda_function" "emergency_button" {
  function_name    = "${var.project_name}-${var.environment}-emergency-button"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "emergency_button.handler"
  runtime          = var.lambda_runtime
  filename         = archive_file.emergency_button_zip.output_path
  source_code_hash = archive_file.emergency_button_zip.output_base64sha256
}

resource "aws_lambda_event_source_mapping" "emergency_sqs" {
  event_source_arn = aws_sqs_queue.emergency.arn
  function_name    = aws_lambda_function.emergency_button.arn
  batch_size       = 10
}

// ----------------------------
// WebSocket API wired to Lambda
// ----------------------------

resource "aws_apigatewayv2_api" "ws" {
  name                       = "${var.project_name}-${var.environment}-ws"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

resource "aws_apigatewayv2_integration" "ws_lambda" {
  api_id                 = aws_apigatewayv2_api.ws.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.websocket_transform.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "ws_connect" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_lambda.id}"
}

resource "aws_apigatewayv2_route" "ws_disconnect" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_lambda.id}"
}

resource "aws_apigatewayv2_route" "ws_default" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.ws_lambda.id}"
}

resource "aws_apigatewayv2_stage" "ws_prod" {
  api_id      = aws_apigatewayv2_api.ws.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_ws.arn
    format = jsonencode({
      requestId   = "$context.requestId",
      ip          = "$context.identity.sourceIp",
      requestTime = "$context.requestTime",
      routeKey    = "$context.routeKey",
      status      = "$context.status",
      protocol    = "$context.protocol"
    })
  }
}

resource "aws_cloudwatch_log_group" "api_ws" {
  name              = "/apigw/${var.project_name}/${var.environment}/ws"
  retention_in_days = 30
}

resource "aws_lambda_permission" "ws_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_transform.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.ws.execution_arn}/*/*"
}

# Optional custom domain for WebSocket API
locals {
  ws_api_custom_domain_enabled = var.root_domain_name != null && var.ws_api_domain_name != null
}

data "aws_route53_zone" "root_ws" {
  count = local.ws_api_custom_domain_enabled ? 1 : 0
  name  = var.root_domain_name
}

resource "aws_acm_certificate" "ws_api" {
  count             = local.ws_api_custom_domain_enabled ? 1 : 0
  domain_name       = var.ws_api_domain_name
  validation_method = "DNS"
}

resource "aws_route53_record" "ws_api_cert_validation" {
  count   = local.ws_api_custom_domain_enabled ? length(aws_acm_certificate.ws_api[0].domain_validation_options) : 0
  name    = aws_acm_certificate.ws_api[0].domain_validation_options[count.index].resource_record_name
  type    = aws_acm_certificate.ws_api[0].domain_validation_options[count.index].resource_record_type
  zone_id = data.aws_route53_zone.root_ws[0].zone_id
  records = [aws_acm_certificate.ws_api[0].domain_validation_options[count.index].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "ws_api" {
  count                   = local.ws_api_custom_domain_enabled ? 1 : 0
  certificate_arn         = aws_acm_certificate.ws_api[0].arn
  validation_record_fqdns = [for r in aws_route53_record.ws_api_cert_validation : r.fqdn]
}

resource "aws_apigatewayv2_domain_name" "ws" {
  count = local.ws_api_custom_domain_enabled ? 1 : 0
  domain_name = var.ws_api_domain_name

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.ws_api[0].certificate_arn
    endpoint_type    = "REGIONAL"
    security_policy  = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "ws" {
  count       = local.ws_api_custom_domain_enabled ? 1 : 0
  api_id      = aws_apigatewayv2_api.ws.id
  domain_name = aws_apigatewayv2_domain_name.ws[0].id
  stage       = aws_apigatewayv2_stage.ws_prod.name
}

resource "aws_route53_record" "ws_api_alias" {
  count   = local.ws_api_custom_domain_enabled ? 1 : 0
  name    = var.ws_api_domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.root_ws[0].zone_id

  alias {
    name                   = aws_apigatewayv2_domain_name.ws[0].domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.ws[0].domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}


