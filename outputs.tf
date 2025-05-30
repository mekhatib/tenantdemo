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

output "instance_ids" {
  description = "IDs of the EC2 instances"
  value       = module.ec2_instances.instance_ids
}

output "instance_private_ips" {
  description = "Private IPs of the EC2 instances"
  value       = module.ec2_instances.private_ips
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    base = module.security_groups.base_sg_id
    app  = module.security_groups.app_sg_id
  }
}

output "service_catalog_portfolio_id" {
  description = "Service Catalog portfolio ID"
  value       = module.service_catalog.portfolio_id
}

output "config_recorder_name" {
  description = "AWS Config recorder name"
  value       = module.drift_detection.config_recorder_name
}

output "ipam_pool_id" {
  description = "IPAM pool ID for subnet allocation"
  value       = module.ipam.subnet_pool_id
}