variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
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

variable "alert_email" {
  description = "Email for monitoring alerts"
  type        = string
}

variable "enable_auto_remediation" {
  description = "Enable automatic drift remediation"
  type        = bool
  default     = false
}

variable "config_rules" {
  description = "AWS Config rules to create"
  type = map(object({
    description                 = string
    source_owner               = string
    source_identifier          = string
    input_parameters           = string
    maximum_execution_frequency = string
    scope = object({
      compliance_resource_id    = string
      compliance_resource_types = list(string)
      tag_key                  = string
      tag_value                = string
    })
  }))
  default = {} # Empty map - will use the module's defaults
}  
