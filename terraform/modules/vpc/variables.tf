variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of two availability zones to use"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for public subnets"
}

variable "private_app_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
  description = "CIDR blocks for private application subnets"
}

variable "private_data_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.30.0/24", "10.0.40.0/24"]
  description = "CIDR blocks for private database subnets"
}

variable "environment" {
  type    = string
  default = "prod"
}