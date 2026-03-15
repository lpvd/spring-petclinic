# terraform/variables.tf

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
  default     = "petclinic"
}

variable "instance_type" {
  description = "Type of EC2 instance"
  type        = string
  default     = "t3.small"
}

variable "db_name" {
  description = "DB name"
  type        = string
  default     = "petclinic"
}

variable "db_username" {
  description = "Login for RDS"
  type        = string
  default     = "petclinic_user"
}

variable "db_password" {
  description = "Password for RDS"
  type        = string
  sensitive   = true
  # no default - it's passed separately to not endup in version control system
}

variable "db_instance_class" {
  description = "Type of RDS instance"
  type        = string
  default     = "db.t3.micro"
}

variable "my_ip" {
  description = "My public API"
  type        = string
}