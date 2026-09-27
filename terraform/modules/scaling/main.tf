data "aws_caller_identity" "current" {}

data "archive_file" "scaler" {
  type        = "zip"
  source_file = "${path.module}/lambda/scale_handler.py"
  output_path = "${path.module}/lambda/scale_handler.zip"
}

resource "aws_iam_role" "scaler_lambda" {
  name = "taskflow-${var.environment}-scaler-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

#tfsec:ignore:aws-iam-no-policy-wildcards -- ecs:DescribeTaskDefinition and ecs:RegisterTaskDefinition do not support resource-level permissions per AWS's IAM action reference; Resource must be "*" for these two actions specifically.
resource "aws_iam_role_policy" "scaler_lambda_policy" {
  name = "taskflow-${var.environment}-scaler-lambda-policy"
  role = aws_iam_role.scaler_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition", "ecs:UpdateService"]
        Resource = "arn:aws:ecs:*:*:service/${var.cluster_name}/${var.service_name}"
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [var.execution_role_arn, var.task_role_arn]
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:*:*:log-group:/aws/lambda/taskflow-${var.environment}-vertical-scaler:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "scaler_xray" {
  role       = aws_iam_role.scaler_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "scaler" {
  function_name    = "taskflow-${var.environment}-vertical-scaler"
  role             = aws_iam_role.scaler_lambda.arn
  runtime          = "python3.12"
  handler          = "scale_handler.handler"
  filename         = data.archive_file.scaler.output_path
  source_code_hash = data.archive_file.scaler.output_base64sha256
  timeout          = 30

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      CLUSTER_NAME = var.cluster_name
      SERVICE_NAME = var.service_name
      TASK_FAMILY  = var.task_family
    }
  }
}

resource "aws_kms_key" "sns_scaling" {
  description             = "CMK for encrypting TaskFlow vertical-scaling SNS topic"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountRootFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchToPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "sns_scaling" {
  name          = "alias/taskflow-${var.environment}-sns-scaling"
  target_key_id = aws_kms_key.sns_scaling.key_id
}

resource "aws_sns_topic" "scaling_alerts" {
  name              = "taskflow-${var.environment}-scaling-alerts"
  kms_master_key_id = aws_kms_key.sns_scaling.arn
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.scaling_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.scaler.arn
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scaler.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.scaling_alerts.arn
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "taskflow-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = var.period
  statistic           = "Average"
  threshold           = var.cpu_high_threshold
  dimensions          = { ClusterName = var.cluster_name, ServiceName = var.service_name }
  alarm_description   = "Sustained high CPU — scale TaskFlow task definition up"
  alarm_actions       = [aws_sns_topic.scaling_alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "taskflow-${var.environment}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = var.period
  statistic           = "Average"
  threshold           = var.cpu_low_threshold
  dimensions          = { ClusterName = var.cluster_name, ServiceName = var.service_name }
  alarm_description   = "Sustained low CPU — scale TaskFlow task definition down"
  alarm_actions       = [aws_sns_topic.scaling_alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "taskflow-${var.environment}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = var.period
  statistic           = "Average"
  threshold           = var.memory_high_threshold
  dimensions          = { ClusterName = var.cluster_name, ServiceName = var.service_name }
  alarm_description   = "Sustained high memory — scale TaskFlow task definition up"
  alarm_actions       = [aws_sns_topic.scaling_alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "memory_low" {
  alarm_name          = "taskflow-${var.environment}-memory-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.evaluation_periods
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = var.period
  statistic           = "Average"
  threshold           = var.memory_low_threshold
  dimensions          = { ClusterName = var.cluster_name, ServiceName = var.service_name }
  alarm_description   = "Sustained low memory — scale TaskFlow task definition down"
  alarm_actions       = [aws_sns_topic.scaling_alerts.arn]
  treat_missing_data  = "notBreaching"
}