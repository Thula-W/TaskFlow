variable "environment" {
  type    = string
  default = "prod"
}

variable "db_secret_arn" {
  type = string
}

data "aws_caller_identity" "current" {}

# -------------------------------------------------------------
# 1. EC2 Instance Role & Profile (for ECS Host instances)
# -------------------------------------------------------------
resource "aws_iam_role" "ec2_instance_role" {
  name = "taskflow-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_role" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "taskflow-${var.environment}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance_role.name
}

# -------------------------------------------------------------
# SSM File-Transfer Bucket (internal CI/CD tooling only — used by
# the aws_ssm connection plugin to move Ansible module code to/from
# private EC2 hosts; holds no application or user data)
# -------------------------------------------------------------
resource "aws_kms_key" "ssm_transfer" {
  description             = "CMK for encrypting the TaskFlow SSM transfer bucket"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAccountRootFullAccess"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

resource "aws_kms_alias" "ssm_transfer" {
  name          = "alias/taskflow-${var.environment}-ssm-transfer"
  target_key_id = aws_kms_key.ssm_transfer.key_id
}

#tfsec:ignore:aws-s3-enable-bucket-logging -- transient CI/CD staging bucket for Ansible SSM file transfer only; holds no application or user data, so access logging adds operational overhead without a corresponding security benefit here.
resource "aws_s3_bucket" "ssm_transfer" {
  bucket        = "taskflow-${var.environment}-ssm-transfer-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.ssm_transfer.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "ssm_transfer" {
  bucket                  = aws_s3_bucket.ssm_transfer.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#tfsec:ignore:aws-iam-no-policy-wildcards -- object-level access inherently requires a /* suffix on the bucket ARN (S3 has no narrower object-path grain here); access is already scoped to this one dedicated bucket, not a wildcarded bucket name.
resource "aws_iam_role_policy" "ssm_transfer_access" {
  name = "taskflow-${var.environment}-ssm-transfer-access"
  role = aws_iam_role.ec2_instance_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "${aws_s3_bucket.ssm_transfer.arn}/*"
    }]
  })
}

# -------------------------------------------------------------
# 2. ECS Task Execution Role (Pull from ECR & fetch Secrets)
# -------------------------------------------------------------
resource "aws_iam_role" "ecs_execution_role" {
  name = "taskflow-${var.environment}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_standard" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "secrets_read_policy" {
  name        = "taskflow-${var.environment}-secrets-read-policy"
  description = "Allows ECS agent to read TaskFlow DB secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [var.db_secret_arn]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_secrets" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.secrets_read_policy.arn
}

# -------------------------------------------------------------
# 3. ECS Task Role (Runtime identity for the running app)
# -------------------------------------------------------------
resource "aws_iam_role" "ecs_task_role" {
  name = "taskflow-${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

output "ec2_instance_profile_arn" { value = aws_iam_instance_profile.ec2_profile.arn }
output "ecs_execution_role_arn" { value = aws_iam_role.ecs_execution_role.arn }
output "ecs_task_role_arn" { value = aws_iam_role.ecs_task_role.arn }
output "ssm_transfer_bucket" { value = aws_s3_bucket.ssm_transfer.bucket }