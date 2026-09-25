variable "environment" {
  type    = string
  default = "prod"
}

variable "vpc_id" {
  type = string
}
variable "private_subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "iam_instance_profile_arn" { type = string }
variable "execution_role_arn" { type = string }
variable "task_role_arn" { type = string }
variable "target_group_arn" { type = string }
variable "db_address" { type = string }
variable "db_secret_arn" { type = string }

# Vertical scaling parameters
variable "task_cpu" {
  type        = number
  default     = 256
  description = "CPU units allocated to TaskFlow container (e.g. 256, 512, 1024)"
}

variable "task_memory" {
  type        = number
  default     = 512
  description = "Memory (MiB) allocated to TaskFlow container"
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Git commit short SHA image tag"
}