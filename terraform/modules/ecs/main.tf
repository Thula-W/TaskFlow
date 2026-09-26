#tfsec:ignore:aws-ecr-repository-customer-key
resource "aws_ecr_repository" "app" {
  name                 = "taskflow-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "taskflow-ecr"
  }
}

#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/taskflow-${var.environment}"
  retention_in_days = 14

  tags = {
    Name = "taskflow-ecs-logs"
  }
}


resource "aws_ecs_cluster" "main" {
  name = "taskflow-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}


data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}


resource "aws_launch_template" "ecs_ec2" {
  name_prefix   = "taskflow-${var.environment}-lt-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "t3.small"

  iam_instance_profile {
    arn = var.iam_instance_profile_arn
  }

  # Require IMDSv2 (tokens)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = var.security_group_ids
  }

  # Configures the host instance to join our ECS cluster
  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "ECS_CLUSTER=${aws_ecs_cluster.main.name}" >> /etc/ecs/ecs.config
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "taskflow-${var.environment}-ecs-host"
      Role        = "ecs-host"
      Environment = var.environment
    }
  }
}


resource "aws_autoscaling_group" "ecs_asg" {
  name_prefix         = "taskflow-${var.environment}-asg-"
  vpc_zone_identifier = var.private_subnet_ids
  min_size            = 1
  max_size            = 3
  desired_capacity    = 2

  launch_template {
    id      = aws_launch_template.ecs_ec2.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "ecs-host"
    propagate_at_launch = true
  }
}


resource "aws_ecs_task_definition" "app" {
  family                   = "taskflow-${var.environment}"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([{
    name      = "taskflow"
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    cpu       = var.task_cpu
    memory    = var.task_memory
    essential = true

    portMappings = [{
      containerPort = 3000
      hostPort      = 3000
      protocol      = "tcp"
    }]

    environment = [
      { name = "NODE_ENV", value = "production" },
      { name = "PORT", value = "3000" },
      { name = "LOG_LEVEL", value = "info" },
      { name = "DATABASE_URL", value = "postgresql://postgres:${var.db_password}@${var.db_address}:5432/taskflow" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
        "awslogs-region"        = "ap-south-1"
        "awslogs-stream-prefix" = "taskflow"
      }
    }
  }])
}

# 8. ECS Service
resource "aws_ecs_service" "app" {
  name            = "taskflow-${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "EC2"

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "taskflow"
    container_port   = 3000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [aws_autoscaling_group.ecs_asg]
}

output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
output "cluster_name" { value = aws_ecs_cluster.main.name }
output "service_name" { value = aws_ecs_service.app.name }