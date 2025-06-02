# Tenant deployment template

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "tfe_workspace" "current" {
  name         = terraform.workspace
  organization = var.tfc_organization
}

# Local values
locals {
  azs = data.aws_availability_zones.available.names
  
  # Pre-calculate expected route table count based on subnet configuration
  expected_private_rt_count = length([for type in ["private", "public"] : type if type == "private"])
  expected_public_rt_count  = length([for type in ["private", "public"] : type if type == "public"]) > 0 ? 1 : 0
  
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Owner       = var.owner_email
    CostCenter  = var.cost_center
  }
}

# IPAM Module - Updated with proper lifecycle management
module "ipam" {
  source  = "app.terraform.io/test-khatib/ipam/aws"
  version = "~> 0.0"
  
  environment     = var.environment
  project_name    = var.project_name
  ipam_pool_cidr  = var.ipam_pool_cidr
  
  tags = local.common_tags
}

# Resource Tagging Module
module "resource_tags" {
  source  = "app.terraform.io/test-khatib/resource-tags/aws"
  version = "~> 0.0"
  
  environment  = var.environment
  project_name = var.project_name
  
  # VLAN allocations
  vlan_allocations = {
    subnet_1 = 100
    subnet_2 = 200
  }
  
  # ASN allocations
  asn_allocations = {
    tgw   = 64512
    vpc_1 = 65001
    vpc_2 = 65002
  }
}

# VPC Module - Updated with proper IPAM dependency management
module "vpc" {
  source  = "app.terraform.io/test-khatib/vpc/aws"
  version = "~> 0.0"
  
  # Basic Configuration
  environment        = var.environment
  project_name       = var.project_name
  availability_zones = slice(local.azs, 0, 2)
  
  # IPAM Configuration
  use_ipam           = true
  ipam_pool_id       = module.ipam.vpc_ipam_pool_id  # Correct output name
  vpc_netmask_length = 20  # Creates a /20 VPC (4096 IPs)
  
  # Subnet Configuration
  subnet_types = ["private", "public"]  # 1 private subnet, 1 public subnet
  vlan_tags    = ["100", "200"]         # Convert numbers to strings to match expected type
  
  # DNS Configuration
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  # Flow Logs Configuration - FIXED: Disabled until IAM role is created
  enable_flow_logs = false  # Changed from true to false
  # flow_log_iam_role_arn and flow_log_destination will use module defaults if not specified
  flow_log_traffic_type = "ALL"
  
  # Tags
  tags = local.common_tags
  
  # Explicit dependency to ensure IPAM is fully created before VPC
  depends_on = [module.ipam]
}

# Transit Gateway Module - SIMPLIFIED: No route creation
module "transit_gateway" {
  source  = "app.terraform.io/test-khatib/transit-gateway/aws"
  version = "~> 0.0"
  
  # Required variables - only the essentials
  environment  = var.environment
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.subnet_ids
  
  # Optional variables
  tgw_asn            = 64512
  enable_dns_support = true
  enable_multicast   = false
  
  # Routes configuration
  tgw_routes = []
  
  # Tags
  tags = local.common_tags
  
  # Ensure VPC is created first
  depends_on = [module.vpc]
}
  
# Security Groups Module
module "security_groups" {
  source  = "app.terraform.io/test-khatib/security-groups/aws"
  version = "~> 0.0"
  
  environment  = var.environment
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr_block
  
  # Base security group rules
  base_ingress_rules = {
    ssh = {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidrs
    }
    http = {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
    https = {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  
  tags = local.common_tags
  
  # Ensure VPC is created first
  depends_on = [module.vpc]
}



# Add cleanup dependency resource to ensure proper destroy order
resource "null_resource" "destroy_order" {
  depends_on = [
    module.transit_gateway,
    module.security_groups,
    module.vpc,
    module.ipam
  ]
  
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Infrastructure destroyed in proper order'"
  }
}
