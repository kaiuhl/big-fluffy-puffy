# bfp-web-1 was created by hand in the Lightsail console and imported into
# state so instance-level settings (daily automatic snapshots) stay
# declarative. prevent_destroy blocks any plan that would replace the box:
# it holds the production Postgres volume, and Lightsail treats most
# attribute changes here as replacements.
resource "aws_lightsail_instance" "bfp_web" {
  name              = "bfp-web-1"
  availability_zone = "us-west-2a"
  blueprint_id      = "ubuntu_24_04"
  bundle_id         = "small_3_0"
  key_pair_name     = "bfp-prod"
  ip_address_type   = "dualstack"

  add_on {
    type          = "AutoSnapshot"
    snapshot_time = "10:00"
    status        = "Enabled"
  }

  tags = {
    Environment = var.environment
    Service     = "web"
  }

  lifecycle {
    prevent_destroy = true
  }
}
