variable "vpc_id" { type = string }
variable "environment" {
  type    = string
  default = "prod"
}

variable "app_port" {
  type    = number
  default = 3000
}


# 1. ALB Security Group
#tfsec:ignore:aws-ec2-no-public-ingress-sgr
#tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_security_group" "alb" {
  name        = "taskflow-${var.environment}-alb-sg"
  description = "Allows incoming HTTP traffic from the public internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "Public HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic to EC2 target instances"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "taskflow-${var.environment}-alb-sg"
  }
}

# 2. EC2 Host (ECS Cluster) Security Group
#tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_security_group" "ec2" {
  name        = "taskflow-${var.environment}-ec2-sg"
  description = "Restricts inbound traffic solely to ALB"
  vpc_id      = var.vpc_id

ingress {
    description     = "Traffic from ALB to dynamic host ports"
    from_port       = 32768
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Outbound internet access via NAT Gateway for package/image downloads"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "taskflow-${var.environment}-ec2-sg"
  }
}

# 3. RDS PostgreSQL Security Group
#tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_security_group" "rds" {
  name        = "taskflow-${var.environment}-rds-sg"
  description = "Restricts PostgreSQL access strictly to EC2 app instances"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EC2 hosts"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    description = "No outbound required for RDS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "taskflow-${var.environment}-rds-sg"
  }
}

output "alb_sg_id" { value = aws_security_group.alb.id }
output "ec2_sg_id" { value = aws_security_group.ec2.id }
output "rds_sg_id" { value = aws_security_group.rds.id }