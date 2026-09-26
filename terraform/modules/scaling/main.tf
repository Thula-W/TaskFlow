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

resource "aws_iam_role_policy" "scaler_lambda_policy" {
  name = "taskflow-${var.environment}-scaler-lambda-policy"
  role = aws_iam_role.scaler_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition", "ecs:UpdateService"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [var.execution_role_arn, var.task_role_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "scaler" {
  function_name    = "taskflow-${var.environment}-vertical-scaler"
  role             = aws_iam_role.scaler_lambda.arn
  runtime          = "python3.12"
  handler          = "scale_handler.handler"
  filename         = data.archive_file.scaler.output_path
  source_code_hash = data.archive_file.scaler.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      CLUSTER_NAME = var.cluster_name
      SERVICE_NAME = var.service_name
      TASK_FAMILY  = var.task_family
    }
  }
}

resource "aws_sns_topic" "scaling_alerts" {
  name = "taskflow-${var.environment}-scaling-alerts"
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
