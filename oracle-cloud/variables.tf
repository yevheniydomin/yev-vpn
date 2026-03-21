variable "compartment_id" {
  description = "OCI compartment OCID (use tenancy OCID for root compartment)"
  type        = string
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "eu-frankfurt-1"
}

variable "ssh_public_key" {
  description = "SSH public key for instance access (optional, for debugging)"
  type        = string
  default     = ""
}

variable "admin_ssh_cidr" {
  description = "CIDR block allowed to SSH into the instance"
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_ocpus" {
  description = "OCPUs for ARM shape (free tier: up to 4)"
  type        = number
  default     = 1
}

variable "instance_memory_gb" {
  description = "Memory in GB for ARM shape (free tier: up to 24)"
  type        = number
  default     = 6
}

variable "availability_domain_index" {
  description = "AD index (0-2). Try different values if 'Out of host capacity'"
  type        = number
  default     = 2
}

variable "shape" {
  description = "Free tier shapes: VM.Standard.E2.1.Micro (x86) or VM.Standard.A1.Flex (ARM)"
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}
