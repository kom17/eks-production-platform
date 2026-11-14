variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_name" {
  description = "Used for kubernetes.io/cluster/<name> subnet discovery tags"
  type        = string
}

variable "cidr" {
  type    = string
  default = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.cidr))
    error_message = "cidr must be a valid IPv4 CIDR block."
  }
}

variable "az_count" {
  type    = number
  default = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4 (EKS needs at least 2 AZs)."
  }
}

variable "single_nat_gateway" {
  description = "true = one shared NAT (cheap, dev). false = one NAT per AZ (HA, prod)."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
