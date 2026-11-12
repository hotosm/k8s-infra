# CDN cache for eoAPI TiTiler tiles, served at https://tiles.imagery.hotosm.org/raster/...
# The origin is the existing api.imagery.hotosm.org ingress, so nothing in-cluster
# changes and that host keeps serving uncached. See hotosm/openaerialmap#381.

locals {
  oam_tiles_host  = "tiles.imagery.hotosm.org"
  oam_origin_host = "api.imagery.hotosm.org"
}

data "aws_route53_zone" "imagery" {
  name         = "imagery.hotosm.org."
  private_zone = false
}

resource "aws_acm_certificate" "oam_tiles" {
  domain_name       = local.oam_tiles_host
  validation_method = "DNS"

  tags = merge(var.tags, {
    environment = var.environment
    project     = "oam"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "oam_tiles_cert_validation" {
  for_each = {
    for o in aws_acm_certificate.oam_tiles.domain_validation_options : o.domain_name => o
  }

  zone_id = data.aws_route53_zone.imagery.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 300
}

resource "aws_acm_certificate_validation" "oam_tiles" {
  certificate_arn         = aws_acm_certificate.oam_tiles.arn
  validation_record_fqdns = [for r in aws_route53_record.oam_tiles_cert_validation : r.fqdn]
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# Item tiles rarely change (re-processed COGs, takedowns). One day bounds staleness
# if an invalidation is missed. min_ttl overrides TiTiler's max-age=3600.
resource "aws_cloudfront_cache_policy" "oam_item_tiles" {
  name        = "oam-item-tiles-${var.environment}"
  min_ttl     = 86400
  default_ttl = 86400
  max_ttl     = 86400

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    # assets, rescale, bidx etc change the render
    query_strings_config {
      query_string_behavior = "all"
    }
    headers_config {
      header_behavior = "none"
    }
    cookies_config {
      cookie_behavior = "none"
    }
  }
}

# Mosaic tiles change as imagery is ingested, so follow TiTiler's max-age=3600.
resource "aws_cloudfront_cache_policy" "oam_mosaic_tiles" {
  name        = "oam-mosaic-tiles-${var.environment}"
  min_ttl     = 0
  default_ttl = 3600
  max_ttl     = 3600

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    query_strings_config {
      query_string_behavior = "all"
    }
    headers_config {
      header_behavior = "none"
    }
    cookies_config {
      cookie_behavior = "none"
    }
  }
}

# Only /raster is served on the tiles host. Anything else redirects to the API
# host, so the tiles host doesn't become an uncached mirror of the whole API.
resource "aws_cloudfront_function" "oam_tiles_redirect" {
  name    = "oam-tiles-redirect-${var.environment}"
  runtime = "cloudfront-js-2.0"
  comment = "Redirect non-raster paths to ${local.oam_origin_host}"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var params = [];
      for (var key in request.querystring) {
        var param = request.querystring[key];
        var values = param.multiValue || [param];
        values.forEach((v) => params.push(v.value === "" ? key : key + "=" + v.value));
      }
      var query = params.length ? "?" + params.join("&") : "";
      return {
        statusCode: 308,
        statusDescription: "Permanent Redirect",
        headers: { location: { value: "https://${local.oam_origin_host}" + request.uri + query } },
      };
    }
  EOT
}

resource "aws_cloudfront_distribution" "oam_tiles" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "OAM TiTiler tile cache"
  aliases         = [local.oam_tiles_host]

  # Host header is not forwarded, so nginx sees api.imagery.hotosm.org and its
  # existing cert and routing apply unchanged.
  origin {
    domain_name = local.oam_origin_host
    origin_id   = "eoapi"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Non-raster paths never reach the origin, see aws_cloudfront_function.oam_tiles_redirect.
  default_cache_behavior {
    target_origin_id       = "eoapi"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_disabled.id
    viewer_protocol_policy = "redirect-to-https"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.oam_tiles_redirect.arn
    }
  }

  # Order matters: `*` matches across `/`, so more specific patterns come first.
  ordered_cache_behavior {
    path_pattern           = "/raster/collections/*/items/*/tiles/*"
    target_origin_id       = "eoapi"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = aws_cloudfront_cache_policy.oam_item_tiles.id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  dynamic "ordered_cache_behavior" {
    for_each = ["/raster/collections/*/tiles/*", "/raster/searches/*/tiles/*"]

    content {
      path_pattern           = ordered_cache_behavior.value
      target_origin_id       = "eoapi"
      allowed_methods        = ["GET", "HEAD", "OPTIONS"]
      cached_methods         = ["GET", "HEAD"]
      cache_policy_id        = aws_cloudfront_cache_policy.oam_mosaic_tiles.id
      viewer_protocol_policy = "redirect-to-https"
      compress               = true
    }
  }

  # Raster paths that aren't tiles (tilejson, api.html, POST /searches/register).
  ordered_cache_behavior {
    path_pattern             = "/raster/*"
    target_origin_id         = "eoapi"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.oam_tiles.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = merge(var.tags, {
    environment = var.environment
    project     = "oam"
  })
}

resource "aws_route53_record" "oam_tiles_alias" {
  for_each = toset(["A", "AAAA"])

  zone_id = data.aws_route53_zone.imagery.zone_id
  name    = local.oam_tiles_host
  type    = each.key

  alias {
    name                   = aws_cloudfront_distribution.oam_tiles.domain_name
    zone_id                = aws_cloudfront_distribution.oam_tiles.hosted_zone_id
    evaluate_target_health = false
  }
}

output "oam_tiles_cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.oam_tiles.id
  description = "OAM tiles CloudFront Distribution ID, for invalidations"
}
