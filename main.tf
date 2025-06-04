terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.51.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "tfe" {
  token = var.tfe_token
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Get current workspace information for state sharing
data "tfe_workspace" "current" {
  name         = var.infrastructure_workspace_name != "" ? var.infrastructure_workspace_name : terraform.workspace
  organization = var.tfc_organization
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
  
  # BGP ASN allocations from resource tags
  bgp_asns = {
    tgw   = 64512
    vpc_1 = 65001
    vpc_2 = 65002
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
  
  vlan_allocations = var.vlan_tags
  
  asn_allocations = local.bgp_asns
}

# VPC Module - Cloud Layer
module "vpc" {
  source  = "app.terraform.io/test-khatib/vpc/aws"
  version = "~> 0.0"
  
  environment        = var.environment
  project_name       = var.project_name
  availability_zones = slice(local.azs, 0, 2)
  
  use_ipam           = true
  ipam_pool_id       = module.ipam.vpc_ipam_pool_id
  vpc_netmask_length = 20  # /20 VPC (4096 IPs)
  
  subnet_types = ["private", "public"]
  vlan_tags    = [for k, v in var.vlan_tags : tostring(v)]
  
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  # Flow logs will be configured separately below
  enable_flow_logs = false
  
  tags = local.common_tags
  
  depends_on = [module.ipam]
}

# Internet Gateway - DCGW Layer Component
resource "aws_internet_gateway" "main" {
  vpc_id = module.vpc.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name  = "${var.project_name}-${var.environment}-igw"
      Layer = "DCGW"
    }
  )
}

# Public Route Table for Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = module.vpc.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-public-rt"
    }
  )
}

# Route to Internet Gateway
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count = length(module.vpc.public_subnet_ids)
  
  subnet_id      = module.vpc.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public.id
}

# Enhanced Transit Gateway - DCGW/SDN Layer
resource "aws_ec2_transit_gateway" "main" {
  description                     = "${var.project_name}-${var.environment}-tgw"
  amazon_side_asn                = local.bgp_asns.tgw
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                    = "enable"
  vpn_ecmp_support              = "enable"
  multicast_support              = var.enable_multicast ? "enable" : "disable"
  
  tags = merge(
    local.common_tags,
    {
      Name  = "${var.project_name}-${var.environment}-tgw"
      Layer = "DCGW"
      Type  = "Multi-Domain-Gateway"
    }
  )
}

# Transit Gateway Route Tables for VRF Simulation
resource "aws_ec2_transit_gateway_route_table" "dcgw" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  
  tags = merge(
    local.common_tags,
    {
      Name  = "${var.project_name}-${var.environment}-dcgw-rt"
      VRF   = "DCGW"
      Layer = "DCGW"
    }
  )
}

resource "aws_ec2_transit_gateway_route_table" "sdn" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  
  tags = merge(
    local.common_tags,
    {
      Name  = "${var.project_name}-${var.environment}-sdn-rt"
      VRF   = "SDN"
      Layer = "SDN"
    }
  )
}

# VPC Attachment - SDN Layer L3Out
resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  subnet_ids         = module.vpc.private_subnet_ids
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id            = module.vpc.vpc_id
  
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  
  tags = merge(
    local.common_tags,
    {
      Name    = "${var.project_name}-${var.environment}-tgw-attach"
      Layer   = "SDN"
      Type    = "L3Out"
      BGP_ASN = local.bgp_asns.vpc_1
    }
  )
}

# Route table associations for VRF simulation
resource "aws_ec2_transit_gateway_route_table_association" "sdn" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.main.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.sdn.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "sdn_to_dcgw" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.main.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dcgw.id
}

# Static routes for SDN simulation
resource "aws_ec2_transit_gateway_route" "sdn_default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.sdn.id
  # This would typically point to a VPN or Direct Connect attachment
  blackhole = true  # Placeholder until VPN/DX is configured
}

# VPC Routes to Transit Gateway
resource "aws_route" "private_to_tgw" {
  count = length(module.vpc.private_subnet_ids)
  
  route_table_id         = data.aws_route_table.private[count.index].id
  destination_cidr_block = "10.0.0.0/8"  # Corporate network
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.main]
}

# Data source to get private route tables
data "aws_route_table" "private" {
  count = length(module.vpc.private_subnet_ids)
  
  subnet_id = module.vpc.private_subnet_ids[count.index]
}

# Route53 Private Hosted Zone - IPAM/DNS Management
resource "aws_route53_zone" "private" {
  name = "${var.project_name}-${var.environment}.internal"

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-private-zone"
      Type = "IPAM-DNS"
    }
  )
}

# VPC Flow Logs Configuration
resource "aws_s3_bucket" "flow_logs" {
  bucket = "${var.project_name}-${var.environment}-flow-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-flow-logs"
    }
  )
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = 30
    }
    
    filter {
      prefix = "flow-logs/"
    }
  }
}

# IAM role for Flow Logs
resource "aws_iam_role" "flow_log" {
  name = "${var.project_name}-${var.environment}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "flow_log" {
  name = "${var.project_name}-${var.environment}-flow-log-policy"
  role = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.flow_logs.arn,
          "${aws_s3_bucket.flow_logs.arn}/*"
        ]
      }
    ]
  })
}

# VPC Flow Log
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_s3_bucket.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = module.vpc.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-flow-log"
    }
  )
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
    bgp = {
      from_port   = 179
      to_port     = 179
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]  # Corporate network
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

# Optional: Customer Gateway for BGP over VPN
resource "aws_customer_gateway" "main" {
  count = var.enable_bgp_vpn ? 1 : 0
  
  bgp_asn    = var.customer_bgp_asn
  ip_address = var.customer_gateway_ip
  type       = "ipsec.1"
  
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-cgw"
    }
  )
}

# Optional: VPN Connection for BGP
resource "aws_vpn_connection" "main" {
  count = var.enable_bgp_vpn ? 1 : 0
  
  customer_gateway_id = aws_customer_gateway.main[0].id
  transit_gateway_id  = aws_ec2_transit_gateway.main.id
  type               = "ipsec.1"
  
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-vpn"
    }
  )
}

# VPN Attachment to Transit Gateway route table
resource "aws_ec2_transit_gateway_route_table_association" "vpn" {
  count = var.enable_bgp_vpn ? 1 : 0
  
  transit_gateway_attachment_id  = aws_vpn_connection.main[0].transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dcgw.id
}

# State sharing configuration documentation
resource "local_file" "state_sharing_config" {
  count = var.create_state_sharing_docs ? 1 : 0
  
  filename = "${path.module}/state-sharing-config.json"
  content = jsonencode({
    infrastructure_workspace = {
      organization = var.tfc_organization
      name         = data.tfe_workspace.current.name
      id           = data.tfe_workspace.current.id
    }
    networking_components = {
      dcgw_layer = {
        transit_gateway_id = aws_ec2_transit_gateway.main.id
        internet_gateway_id = aws_internet_gateway.main.id
        bgp_asn = local.bgp_asns.tgw
      }
      sdn_layer = {
        vpc_attachment_id = aws_ec2_transit_gateway_vpc_attachment.main.id
        route_table_ids = {
          dcgw = aws_ec2_transit_gateway_route_table.dcgw.id
          sdn  = aws_ec2_transit_gateway_route_table.sdn.id
        }
      }
      cloud_layer = {
        vpc_id = module.vpc.vpc_id
        subnet_ids = module.vpc.subnet_ids
        vlan_tags = var.vlan_tags  # Use variable instead of module output
      }
    }
  })
}
