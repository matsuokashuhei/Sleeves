variable "zone_id" {
  description = "Cloudflare DNS Zone ID for cacheandbuffer.com"
  type        = string
}

variable "state_bucket_name" {
  description = "Cloudflare R2 bucket name for Terraform state"
  type        = string
  default     = "sleeves-terraform-state"
}
