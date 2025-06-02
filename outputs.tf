output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "subnet_ids" {
  description = "IDs of the subnets"
  value       = module.vpc.private_subnet_ids
}

output "transit_gateway_id" {
  description = "ID of the Transit Gateway"
  value       = module.transit_gateway.tgw_id
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    base = module.security_groups.base_sg_id
    app  = module.security_groups.app_sg_id
  }
}

output "ipam_pool_id" {
  description = "The ID of the IPAM pool used for VPC allocation"
  value       = module.ipam.vpc_ipam_pool_id
}

# Workspace Information
output "workspace_name" {
  description = "Name of the current Terraform workspace"
  value       = terraform.workspace
}

output "tfc_organization" {
  description = "Terraform Cloud organization name"
  value       = var.tfc_organization  # You need to add this variable to your base infrastructure
}

output "workspace_id" {
  description = "Terraform Cloud workspace ID"
  value       = data.tfe_workspace.current.id
}

output "workspace_full_name" {
  description = "Full workspace name for remote state reference"
  value       = "${var.tfc_organization}/${terraform.workspace}"
}
