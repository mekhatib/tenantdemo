# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "all_subnet_ids" {
  description = "All subnet IDs"
  value       = module.vpc.subnet_ids
}

# Transit Gateway Outputs
output "transit_gateway_id" {
  description = "ID of the Transit Gateway"
  value       = module.transit_gateway.tgw_id
}

# Security Group Outputs
output "base_security_group_id" {
  description = "Base security group ID"
  value       = module.security_groups.base_sg_id
}

output "app_security_group_id" {
  description = "Application security group ID"
  value       = module.security_groups.app_sg_id
}

# IAM Outputs
output "instance_role_name" {
  description = "Name of the IAM instance role"
  value       = module.iam_roles.instance_role_name
}

output "instance_role_arn" {
  description = "ARN of the IAM instance role"
  value       = module.iam_roles.instance_role_arn
}

# IPAM Outputs
output "ipam_pool_id" {
  description = "The ID of the IPAM pool used for VPC allocation"
  value       = module.ipam.vpc_ipam_pool_id
}

# Common tags for compute module
output "common_tags" {
  description = "Common tags to be used by compute module"
  value       = local.common_tags
}

# Pass through basic configuration
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}
