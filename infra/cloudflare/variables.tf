variable "zone_id" {
  description = "Cloudflare DNS Zone ID for cacheandbuffer.com"
  type        = string
}

variable "project_name" {
  description = "Cloudflare Pages project name"
  type        = string
  default     = "sleeves-web"
}

variable "subdomain" {
  description = "Subdomain label for Sleeves site"
  type        = string
  default     = "sleeves"
}
