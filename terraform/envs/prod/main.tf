data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source             = "../../modules/vpc"
  environment        = var.environment
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "security" {
  source      = "../../modules/security"
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
}

module "rds" {
  source             = "../../modules/rds"
  environment        = var.environment
  subnet_ids         = module.vpc.private_data_subnet_ids
  security_group_ids = [module.security.rds_sg_id]
}

module "iam" {
  source        = "../../modules/iam"
  environment   = var.environment
  db_secret_arn = module.rds.db_secret_arn
}

module "alb" {
  source             = "../../modules/alb"
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  security_group_ids = [module.security.alb_sg_id]
}

module "ecs" {
  source                   = "../../modules/ecs"
  environment              = var.environment
  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_app_subnet_ids
  security_group_ids       = [module.security.ec2_sg_id]
  iam_instance_profile_arn = module.iam.ec2_instance_profile_arn
  execution_role_arn       = module.iam.ecs_execution_role_arn
  task_role_arn            = module.iam.ecs_task_role_arn
  target_group_arn         = module.alb.target_group_arn
  db_address               = module.rds.db_address
  db_secret_arn            = module.rds.db_secret_arn
  task_cpu                 = var.task_cpu
  task_memory              = var.task_memory
  image_tag                = var.image_tag
  db_password              = module.rds.db_password
}