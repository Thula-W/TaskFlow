output "alb_dns_name" {
  description = "Public URL of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "ecr_repository_url" {
  description = "ECR Repository URL to push application images"
  value       = module.ecs.ecr_repository_url
}

output "rds_endpoint" {
  description = "Internal endpoint of the RDS database"
  value       = module.rds.db_endpoint
}