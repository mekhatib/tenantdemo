terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# Local values
locals {
  azs = data.aws_availability_zones.available.names
  
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Owner       = var.owner_email
    CostCenter  = var.cost_center
  }
}

# IPAM Module
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
  
  vlan_allocations = {
    subnet_1 = 100
    subnet_2 = 200
  }
  
  asn_allocations = {
    tgw   = 64512
    vpc_1 = 65001
    vpc_2 = 65002
  }
}

# VPC Module
module "vpc" {
  source  = "app.terraform.io/test-khatib/vpc/aws"
  version = "~> 0.0"
  
  environment        = var.environment
  project_name       = var.project_name
  availability_zones = slice(local.azs, 0, 2)
  
  use_ipam           = true
  ipam_pool_id       = module.ipam.vpc_ipam_pool_id
  vpc_netmask_length = 20
  
  subnet_types = ["private", "public"]
  vlan_tags    = ["100", "200"]
  
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  enable_flow_logs      = false
  flow_log_traffic_type = "ALL"
  
  tags = local.common_tags
  
  #depends_on = [module.ipam]
}

# Transit Gateway Module
module "transit_gateway" {
  source  = "app.terraform.io/test-khatib/transit-gateway/aws"
  version = "~> 0.0"
  
  environment  = var.environment
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.subnet_ids
  
  tgw_asn            = 64512
  enable_dns_support = true
  enable_multicast   = false
  
  tgw_routes = []
  
  tags = local.common_tags
  
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
  
  depends_on = [module.vpc]
}

# IAM Roles Module
module "iam_roles" {
  source  = "app.terraform.io/test-khatib/iam-roles/aws"
  version = "~> 0.0"
  
  environment  = var.environment
  project_name = var.project_name
  
  managed_policies = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
  
  enable_ec2_operations = true
  
  tags = local.common_tags
}
