data "cloudflare_zone" "cacheandbuffercom" {
  zone_id = var.zone_id
}

locals {
  account_id = data.cloudflare_zone.cacheandbuffercom.account.id
}

resource "cloudflare_r2_bucket" "terraform_state" {
  account_id = local.account_id
  name       = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}
