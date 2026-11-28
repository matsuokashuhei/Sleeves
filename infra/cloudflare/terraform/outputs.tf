output "account_id" {
  description = "Cloudflare Account ID"
  value       = local.account_id
}

output "state_bucket_name" {
  description = "R2 bucket name for Terraform state"
  value       = cloudflare_r2_bucket.terraform_state.name
}

output "r2_s3_endpoint" {
  description = "S3-compatible R2 endpoint URL for backend.hcl"
  value       = "https://${local.account_id}.r2.cloudflarestorage.com"
}
