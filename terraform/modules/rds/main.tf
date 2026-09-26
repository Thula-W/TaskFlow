variable "environment" {
  type    = string
  default = "prod"
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}


resource "aws_db_subnet_group" "rds" {
  name       = "taskflow-${var.environment}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "taskflow-${var.environment}-db-subnet-group"
  }
}


resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "db_secret" {
  name                    = "taskflow-${var.environment}-db-credentials-v2"
  recovery_window_in_days = 0 # Immediate deletion upon terraform destroy

  tags = {
    Name = "taskflow-${var.environment}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_secret_val" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = "postgres"
    password = random_password.db_password.result
    database = "taskflow"
    port     = 5432
  })
}


#tfsec:ignore:aws-rds-enable-performance-insights
#tfsec:ignore:aws-rds-encrypt-instance-storage-data
#tfsec:ignore:aws-rds-specify-backup-retention
resource "aws_db_instance" "postgres" {
  identifier             = "taskflow-${var.environment}-postgres"
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  max_allocated_storage  = 50
  storage_type           = "gp3"
  publicly_accessible    = false
  storage_encrypted      = true
  backup_retention_period = 1
  iam_database_authentication_enabled = true
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = var.security_group_ids
  db_name                = "taskflow"
  username               = "postgres"
  password               = random_password.db_password.result
  skip_final_snapshot    = true
  deletion_protection    = true

  tags = {
    Name = "taskflow-${var.environment}-postgres"
  }
}

output "db_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "db_address" {
  value = aws_db_instance.postgres.address
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db_secret.arn
}

output "db_password" {
  description = "RDS master password"
  value       = jsondecode(aws_secretsmanager_secret_version.db_secret_val.secret_string)["password"]
  sensitive   = true
}
