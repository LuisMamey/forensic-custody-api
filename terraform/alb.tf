# Security Group for Public Application Load Balancer
resource "aws_security_group" "alb" {
  name        = "forensic-custody-alb-sg"
  description = "Ingress security group for external ALB terminating TLS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow inbound HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow egress to private subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
  }

  tags = {
    Name        = "forensic-custody-alb-sg"
    Environment = "production"
    Project     = "forensic-custody-api"
  }
}

# AWS Application Load Balancer (ALB) deployed across public DMZ subnets
resource "aws_lb" "api" {
  #checkov:skip=CKV_AWS_91:Accepted risk — see docs/adr/0005-alb-security-scope.md
  #checkov:skip=CKV_AWS_150:Accepted risk — see docs/adr/0005-alb-security-scope.md
  #checkov:skip=CKV2_AWS_76:Accepted risk — see docs/adr/0005-alb-security-scope.md
  name               = "forensic-custody-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  drop_invalid_header_fields = true

  tags = {
    Environment = "production"
    Project     = "forensic-custody-api"
  }
}
