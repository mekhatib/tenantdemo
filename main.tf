# environments/dev/main.tf

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"] # Amazon's official AMIs
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
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

# IAM Roles Module
module "iam_roles" {
  source  = "app.terraform.io/test-khatib/iam-roles/aws"
  version = "~> 0.0"
  
  environment  = var.environment
  project_name = var.project_name
  
  # Add AWS managed policies for SSM and CloudWatch
  managed_policies = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
  
  # Enable EC2 operations (already default true)
  enable_ec2_operations = true
  
  tags = local.common_tags
}

# Create key pair
resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-${var.environment}-keypair"
  public_key = tls_private_key.main.public_key_openssh
  
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-keypair"
    }
  )
}

# EC2 Instances Module
module "ec2_instances" {
  source  = "app.terraform.io/test-khatib/ec2-instances/aws"
  version = "~> 0.0"
  
  environment  = var.environment
  project_name = var.project_name
  
  # The module expects a list of instance configurations
  instances = [
    {
      name               = "${var.project_name}-${var.environment}-instance-1"
      instance_type      = var.instance_types["flavor1"]
      subnet_id          = length(module.vpc.private_subnet_ids) > 0 ? module.vpc.private_subnet_ids[0] : module.vpc.subnet_ids[0]
      security_group_ids = [module.security_groups.app_sg_id]
      iam_role_name      = module.iam_roles.instance_role_name
      user_data_file     = null
      tags               = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-instance-1" })
    },
    {
      name               = "${var.project_name}-${var.environment}-instance-2"
      instance_type      = var.instance_types["flavor2"]
      subnet_id          = length(module.vpc.private_subnet_ids) > 1 ? module.vpc.private_subnet_ids[1] : (length(module.vpc.subnet_ids) > 1 ? module.vpc.subnet_ids[1] : module.vpc.subnet_ids[0])
      security_group_ids = [module.security_groups.app_sg_id]
      iam_role_name      = module.iam_roles.instance_role_name
      user_data_file     = null
      tags               = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-instance-2" })
    }
  ]
  
  # Other required/optional parameters
  ami_id                   = data.aws_ami.amazon_linux.id
  key_name                 = aws_key_pair.main.key_name
  root_volume_size         = 20
  assign_elastic_ips       = true
  elastic_ip_allocation_ids = []  # Let module create new EIPs
  create_dns_records       = false  # Disable since no Route53 zone available
  route53_zone_id          = null  # VPC module doesn't create Route53 zone
  route53_zone_name        = "${var.project_name}-${var.environment}.internal"
  enable_monitoring        = false
  cpu_alarm_threshold      = 80
  alarm_actions           = []  # Will be populated if monitoring module provides SNS topic
  create_instance_profiles = true  # We're using IAM roles from iam_roles module
  additional_volumes      = []
  kms_key_id              = null
  
  # Ensure all dependencies are created first
  depends_on = [
    module.vpc,
    module.security_groups,
    module.iam_roles,
    aws_key_pair.main
  ]
}

# Add cleanup dependency resource to ensure proper destroy order
resource "null_resource" "destroy_order" {
  depends_on = [
    module.ec2_instances,
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
