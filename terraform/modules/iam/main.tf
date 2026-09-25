variable "environment" {
  type    = string
  default = "prod"
}

variable "db_secret_arn" {
  type = string
}

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

# IAM Instance Profile referenced by the Launch Template
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "taskflow-${var.environment}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance_role.name
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