variable "environment"        { type = string }
variable "cluster_name"       { type = string }
variable "service_name"       { type = string }
variable "task_family"        { type = string }
variable "execution_role_arn" { type = string }
variable "task_role_arn"      { type = string }

variable "cpu_high_threshold"    { type = number, default = 75 }
variable "cpu_low_threshold"     { type = number, default = 20 }
variable "memory_high_threshold" { type = number, default = 75 }
variable "memory_low_threshold"  { type = number, default = 20 }
variable "evaluation_periods"    { type = number, default = 3 }
variable "period"                { type = number, default = 60 }
