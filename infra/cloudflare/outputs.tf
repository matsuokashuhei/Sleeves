output "pages_project_name" {
  description = "Cloudflare Pages project name"
  value       = cloudflare_pages_project.sleeves.name
}

output "pages_subdomain" {
  description = "Default Cloudflare Pages subdomain (*.pages.dev)"
  value       = cloudflare_pages_project.sleeves.subdomain
}

output "custom_domain_url" {
  description = "Production custom domain URL"
  value       = "https://${cloudflare_pages_domain.sleeves.name}"
}
