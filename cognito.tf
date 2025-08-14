// ---------------------------------------------------------------------------------------
// Cognito User Pool for authentication
// - User pool with email sign-in
// - App client configured for OAuth2 (code flow)
// - Hosted domain for the Cognito Hosted UI
// ---------------------------------------------------------------------------------------

resource "aws_cognito_user_pool" "this" {
  name = "${var.project_name}-${var.environment}-users"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.project_name}-${var.environment}-web"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                       = false
  prevent_user_existence_errors         = "ENABLED"
  enable_token_revocation               = true
  supported_identity_providers          = ["COGNITO"]
  allowed_oauth_flows_user_pool_client  = true
  allowed_oauth_flows                   = ["code"]
  allowed_oauth_scopes                  = ["openid", "email", "profile"]
  callback_urls                         = var.cognito_callback_urls
  logout_urls                           = var.cognito_logout_urls
  explicit_auth_flows                   = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}


