variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "rfp-poc"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "ipam_pool_cidr" {
  description = "IPAM pool CIDR for dynamic allocation"
  type        = string
  default     = "10.0.0.0/8"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

variable "owner_email" {
  description = "Owner email for notifications"
  type        = string
}

# Terraform Cloud Configuration
variable "tfc_organization" {
  description = "Terraform Cloud organization name"
  type        = string
}

variable "infrastructure_workspace_name" {
  description = "Override workspace name if different from current"
  type        = string
  default     = ""
}

variable "tfe_token" {
  description = "Terraform Cloud API token"
  type        = string
  sensitive   = true
}

variable "enable_global_state_sharing" {
  description = "Enable global remote state sharing within the organization"
  type        = bool
  default     = true
}

variable "create_state_sharing_docs" {
  description = "Create a JSON file documenting state sharing configuration"
  type        = bool
  default     = true
}

# BGP/VPN Configuration
variable "enable_bgp_vpn" {
  description = "Enable VPN connection for BGP"
  type        = bool
  default     = false
}

variable "customer_bgp_asn" {
  description = "Customer side BGP ASN"
  type        = number
  default     = 65000
}

variable "customer_gateway_ip" {
  description = "Customer gateway public IP address"
  type        = string
  default     = ""
}

variable "enable_multicast" {
  description = "Enable multicast support on Transit Gateway"
  type        = bool
  default     = false
}
