data "cloudflare_zone" "cacheandbuffercom" {
  zone_id = var.zone_id
}

locals {
  account_id    = data.cloudflare_zone.cacheandbuffercom.account.id
  custom_domain = "${var.subdomain}.${data.cloudflare_zone.cacheandbuffercom.name}"
}

resource "cloudflare_pages_project" "sleeves" {
  account_id        = local.account_id
  name              = var.project_name
  production_branch = "main"
}

resource "cloudflare_pages_domain" "sleeves" {
  account_id   = local.account_id
  project_name = cloudflare_pages_project.sleeves.name
  name         = local.custom_domain
}

resource "cloudflare_dns_record" "sleeves" {
  zone_id = data.cloudflare_zone.cacheandbuffercom.zone_id
  name    = local.custom_domain
  type    = "CNAME"
  content = cloudflare_pages_project.sleeves.subdomain
  proxied = true
  ttl     = 1
}
