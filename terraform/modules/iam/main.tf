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



# Attach standard AWS managed policies for ECS on EC2 & CloudWatch
resource "aws_iam_role_policy_attachment" "ecs_ec2_role" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Allows SSM Session Manager to reach these instances without SSH/public IP —
# required because the hosts sit in private subnets with no inbound port 22 path.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile referenced by the Launch Template
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "taskflow-${var.environment}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance_role.name
}

# -------------------------------------------------------------
# SSM File-Transfer Bucket (used by the aws_ssm connection plugin
# to move Ansible module code to/from the private EC2 hosts)
# -------------------------------------------------------------
#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket" "ssm_transfer" {
  bucket        = "taskflow-${var.environment}-ssm-transfer-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "ssm_transfer" {
  bucket                  = aws_s3_bucket.ssm_transfer.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

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

# Custom policy to read DB credentials from Secrets Manager
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