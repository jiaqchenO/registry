resource "aws_api_gateway_rest_api" "api" {
  name        = "opentf-registry"
  description = "API Gateway for the OpenTF Registry"
}

resource "aws_api_gateway_resource" "v1_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "v1"
}

resource "aws_api_gateway_resource" "providers_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.v1_resource.id
  path_part   = "providers"
}

resource "aws_api_gateway_resource" "namespace_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.providers_resource.id
  path_part   = "{namespace}"
}

resource "aws_api_gateway_resource" "type_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.namespace_resource.id
  path_part   = "{type}"
}

resource "aws_api_gateway_resource" "provider_versions_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.type_resource.id
  path_part   = "versions"
}

resource "aws_api_gateway_resource" "version_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.type_resource.id
  path_part   = "{version}"
}

resource "aws_api_gateway_resource" "download_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.version_resource.id
  path_part   = "download"
}

resource "aws_api_gateway_resource" "os_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.download_resource.id
  path_part   = "{os}"
}

resource "aws_api_gateway_resource" "arch_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.os_resource.id
  path_part   = "{arch}"
}

resource "aws_api_gateway_method" "download_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.arch_resource.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.namespace" = true,
    "method.request.path.type"      = true,
    "method.request.path.version"   = true,
    "method.request.path.os"        = true,
    "method.request.path.arch"      = true,
  }
}

resource "aws_api_gateway_integration" "download_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.arch_resource.id
  http_method = aws_api_gateway_method.download_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.function.invoke_arn

  cache_key_parameters = [
    "method.request.path.namespace",
    "method.request.path.type",
    "method.request.path.version",
    "method.request.path.os",
    "method.request.path.arch",
  ]
}

resource "aws_api_gateway_method" "provider_list_versions_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.provider_versions_resource.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.namespace" = true,
    "method.request.path.type"      = true,
    "method.request.path.version"   = true,
    "method.request.path.os"        = true,
    "method.request.path.arch"      = true,
  }
}

resource "aws_api_gateway_integration" "provider_list_versions_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.provider_versions_resource.id
  http_method = aws_api_gateway_method.provider_list_versions_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.function.invoke_arn

  cache_key_parameters = [
    "method.request.path.namespace",
    "method.request.path.type",
  ]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_method.download_method,
    aws_api_gateway_integration.download_integration,

    aws_api_gateway_method.provider_list_versions_method,
    aws_api_gateway_integration.provider_list_versions_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    # Ensure that redeployment happens every time
    redeployment = timestamp()
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage" {
  deployment_id         = aws_api_gateway_deployment.deployment.id
  rest_api_id           = aws_api_gateway_rest_api.api.id
  stage_name            = "opentf-registry"


  cache_cluster_enabled = true
  cache_cluster_size    = "0.5"
}

resource "aws_api_gateway_method_settings" "download_method_settings" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name

  # This encodes `/` as `~1` to provide the correct path for the method
  method_path = "~1v1~1providers~1{namespace}~1{type}~1{version}~1download~1{os}~1{arch}/GET"

  settings {
    metrics_enabled                         = true
    caching_enabled                         = true
    cache_ttl_in_seconds                    = 3600
    require_authorization_for_cache_control = false
  }
}

resource "aws_api_gateway_method_settings" "provider_list_versions_method_settings" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name

  # This encodes `/` as `~1` to provide the correct path for the method
  method_path = "~1v1~1providers~1{namespace}~1{type}~1versions/GET"

  settings {
    metrics_enabled                         = true
    caching_enabled                         = true
    cache_ttl_in_seconds                    = 3600
    require_authorization_for_cache_control = false
  }
}

output "base_url" {
  description = "Base URL for API Gateway stage."
  value       = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.stage.stage_name}/"
}