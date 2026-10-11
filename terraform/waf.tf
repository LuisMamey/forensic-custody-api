# AWS WAF v2 Web ACL providing edge protection against OWASP Top 10 and Layer 7 DDoS
resource "aws_wafv2_web_acl" "api_waf" {
  name        = "forensic-custody-waf"
  description = "Web ACL protecting forensic custody API against OWASP Top 10 and abusive traffic"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Rule 1: Layer 7 Rate Limiting (Mitigate DoS / brute force)
  rule {
    name     = "RateLimit500RequestsPer5Min"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 500
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ForensicApiRateLimit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed Rules Common Rule Set (OWASP Top 10)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
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
      cloudwatch_metrics_enabled = true
      metric_name                = "ForensicApiCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: AWS Managed Rules Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ForensicApiKnownBadInputs"
      sampled_requests_enabled   = true
    }
  }


  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ForensicApiWafWebAcl"
    sampled_requests_enabled   = true
  }

  tags = {
    Environment = "production"
    Project     = "forensic-custody-api"
  }
}

# Associate AWS WAF Web ACL with the Application Load Balancer
resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_lb.api.arn
  web_acl_arn  = aws_wafv2_web_acl.api_waf.arn
}

# CloudWatch Log Group for AWS WAF audit logs (AWS requires aws-waf-logs- prefix)
resource "aws_cloudwatch_log_group" "waf_logs" {
  name              = "aws-waf-logs-forensic-custody"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.evidence.arn

  tags = {
    Environment = "production"
    Project     = "forensic-custody-api"
  }
}

# Logging configuration sending full WAF inspection logs to CloudWatch
resource "aws_wafv2_web_acl_logging_configuration" "api" {
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs.arn]
  resource_arn            = aws_wafv2_web_acl.api_waf.arn
}
