# environments/dev/main.tf

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
  version = "~> 1.0"
  
  environment          = var.environment
  project_name         = var.project_name
  ipam_cidr           = var.ipam_pool_cidr
  enable_ipam_pool    = true
  delegation_accounts = []
  
  tags = local.common_tags
}

# Resource Tagging Module
module "resource_tags" {
  source  = "app.terraform.io/test-khatib/resource-tags/aws"
  version = "~> 1.0"
  
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

# VPC Module
module "vpc" {
  source  = "app.terraform.io/test-khatib/vpc/aws"
  version = "~> 1.0"
  
  environment        = var.environment
  project_name       = var.project_name
  availability_zones = slice(local.azs, 0, 2)
  ipam_pool_id      = module.ipam.vpc_pool_id
  vlan_tags         = [100, 200]
  
  # VPC settings
  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_flow_logs     = true
  flow_log_retention   = 7
  create_private_zone  = true
  
  tags = local.common_tags
}

# Transit Gateway Module
module "transit_gateway" {
  source  = "app.terraform.io/test-khatib/transit-gateway/aws"
  version = "~> 1.0"
  
  environment  = var.environment
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  ipam_pool_id = module.ipam.tgw_pool_id
  
  # TGW attachments
  vpc_attachments = {
    main = {
      vpc_id     = module.vpc.vpc_id
      subnet_ids = module.vpc.transit_gateway_subnet_ids
      dns_support = true
      ipv6_support = false
    }
  }
  
  # Route configurations
  static_routes = []
  
  tags = local.common_tags
}

# Security Groups Module
module "security_groups" {
  source  = "app.terraform.io/test-khatib/security-groups/aws"
  version = "~> 1.0"
  
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
}

# IAM Roles Module
module "iam_roles" {
  source  = "app.terraform.io/test-khatib/iam-roles/aws"
  version = "~> 1.0"
  
  environment  = var.environment
  project_name = var.project_name
  
  # Instance profile
  create_instance_profile = true
  
  # SSM permissions
  enable_ssm_access = true
  
  # CloudWatch permissions
  enable_cloudwatch_logs = true
  
  # S3 permissions
  s3_bucket_arns = []
  
  tags = local.common_tags
}

# EC2 Instances Module
module "ec2_instances" {
  source  = "app.terraform.io/test-khatib/ec2-instances/aws"
  version = "~> 1.0"
  
  environment         = var.environment
  project_name        = var.project_name
  availability_zones  = slice(local.azs, 0, 2)
  subnet_ids         = module.vpc.app_subnet_ids
  security_group_ids = [module.security_groups.app_security_group_id]
  
  # EC2 configuration
  ami_id                = data.aws_ami.amazon_linux.id
  key_name              = var.key_pair_name
  assign_elastic_ips    = true
  route53_zone_id       = module.vpc.private_zone_id
  create_dns_records    = true
  
  # Instance specifications
  instance_types = var.instance_types
  
  # IAM
  iam_instance_profile_name = module.iam_roles.instance_profile_name
  
  tags = local.common_tags
}

# Monitoring Module
module "monitoring" {
  source  = "app.terraform.io/test-khatib/monitoring/aws"
  version = "~> 1.0"
  
  environment  = var.environment
  project_name = var.project_name
  
  # Resources to monitor
  monitored_resources = {
    vpc_id             = module.vpc.vpc_id
    instance_ids       = module.ec2_instances.instance_ids
    transit_gateway_id = module.transit_gateway.tgw_id
  }
  
  # Enable drift detection
  enable_config_rules = true
  
  # Config rules (let module use defaults or pass custom)
  config_rules = var.config_rules
  
  # SNS topic for alerts
  alert_emails = [var.alert_email]
  
  tags = local.common_tags
}

# Data source for AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}