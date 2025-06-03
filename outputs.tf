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

output "private_route_table_ids" {
  description = "Private route table IDs"
  value       = module.vpc.private_route_table_ids
}

output "public_route_table_id" {
  description = "Public route table ID"
  value       = aws_route_table.public.id
}

# DCGW Layer Outputs
output "internet_gateway_id" {
  description = "ID of the Internet Gateway (DCGW simulation)"
  value       = aws_internet_gateway.main.id
}

output "transit_gateway_id" {
  description = "ID of the Transit Gateway (DCGW/SDN bridge)"
  value       = aws_ec2_transit_gateway.main.id
}

output "transit_gateway_arn" {
  description = "ARN of the Transit Gateway"
  value       = aws_ec2_transit_gateway.main.arn
}

output "dcgw_route_table_id" {
  description = "DCGW VRF route table ID"
  value       = aws_ec2_transit_gateway_route_table.dcgw.id
}

# SDN Layer Outputs
output "sdn_route_table_id" {
  description = "SDN VRF route table ID"
  value       = aws_ec2_transit_gateway_route_table.sdn.id
}

output "vpc_attachment_id" {
  description = "Transit Gateway VPC attachment ID (L3Out)"
  value       = aws_ec2_transit_gateway_vpc_attachment.main.id
}

# Security Group Outputs
output "base_security_group_id" {
  description = "Base security group ID"
  value       = module.security_groups.base_sg_id
}

output "app_security_group_id" {
  description = "Application security group ID (Floating L3Out)"
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

# IPAM/DNS Outputs
output "ipam_pool_id" {
  description = "The ID of the IPAM pool used for VPC allocation"
  value       = module.ipam.vpc_ipam_pool_id
}

output "route53_zone_id" {
  description = "ID of the Route53 private hosted zone"
  value       = aws_route53_zone.private.zone_id
}

output "route53_zone_name" {
  description = "Name of the Route53 private hosted zone"
  value       = aws_route53_zone.private.name
}

# Flow Logs Outputs
output "flow_logs_bucket" {
  description = "S3 bucket for VPC flow logs"
  value       = aws_s3_bucket.flow_logs.id
}

output "flow_log_id" {
  description = "ID of the VPC flow log"
  value       = aws_flow_log.main.id
}

# BGP/ASN Information
output "bgp_asn_allocation" {
  description = "BGP ASN allocations for all layers"
  value = {
    dcgw_tgw = local.bgp_asns.tgw
    vpc_1    = local.bgp_asns.vpc_1
    vpc_2    = local.bgp_asns.vpc_2
  }
}

# VLAN Information
output "vlan_allocations" {
  description = "VLAN tag allocations"
  value       = module.resource_tags.vlan_allocations
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

# Networking Architecture Summary
output "architecture_summary" {
  description = "Summary of the deployed networking architecture"
  value = {
    dcgw_layer = {
      transit_gateway = aws_ec2_transit_gateway.main.id
      internet_gateway = aws_internet_gateway.main.id
      bgp_asn = local.bgp_asns.tgw
    }
    sdn_layer = {
      vpc_attachment = aws_ec2_transit_gateway_vpc_attachment.main.id
      route_tables = {
        dcgw = aws_ec2_transit_gateway_route_table.dcgw.id
        sdn  = aws_ec2_transit_gateway_route_table.sdn.id
      }
    }
    cloud_layer = {
      vpc_id = module.vpc.vpc_id
      subnets = {
        private = module.vpc.private_subnet_ids
        public  = module.vpc.public_subnet_ids
      }
      vlan_tags = module.resource_tags.vlan_allocations
    }
    ipam_dns = {
      ipam_pool = module.ipam.vpc_ipam_pool_id
      dns_zone  = aws_route53_zone.private.zone_id
    }
  }
}

# VPN/BGP Status (if enabled)
output "bgp_vpn_status" {
  description = "BGP VPN connection status"
  value = var.enable_bgp_vpn ? {
    customer_gateway_id = aws_customer_gateway.main[0].id
    vpn_connection_id   = aws_vpn_connection.main[0].id
    vpn_state          = "Check AWS Console for tunnel status"
  } : {
    status = "BGP VPN not enabled"
  }
}
