# ────────────────────────────────────────────────────────────────────
#  Build + push sample-app images to ACR.
#
#  ACR Tasks build remotely — no Docker daemon required on the runner.
#  A Python 3.12 helper handles the build (Terraform can provision an
#  ACR, but cannot natively trigger an `az acr build`).
# ────────────────────────────────────────────────────────────────────
resource "null_resource" "build_images" {
  triggers = {
    acr_name      = module.registry.name
    frontend_hash = sha256(join("", [
      filesha256("${path.module}/../sample-app/frontend/app.py"),
      filesha256("${path.module}/../sample-app/frontend/requirements.txt"),
      filesha256("${path.module}/../sample-app/frontend/Dockerfile"),
    ]))
    backend_hash = sha256(join("", [
      filesha256("${path.module}/../sample-app/backend/server.js"),
      filesha256("${path.module}/../sample-app/backend/package.json"),
      filesha256("${path.module}/../sample-app/backend/Dockerfile"),
    ]))
  }

  provisioner "local-exec" {
    command = "az acr build --registry ${self.triggers.acr_name} --image frontend:latest ${path.module}/../sample-app/frontend && az acr build --registry ${self.triggers.acr_name} --image backend:latest ${path.module}/../sample-app/backend"
  }

  depends_on = [module.registry]
}

# ────────────────────────────────────────────────────────────────────
#  Sample app manifests — render with ACR login server then apply
# ────────────────────────────────────────────────────────────────────
locals {
  sample_app_yaml = templatefile(
    "${path.module}/../kubernetes/sample-app/manifests.yaml.tftpl",
    {
      acr_login_server = module.registry.login_server
    }
  )
}

data "kubectl_file_documents" "sample_app" {
  content = local.sample_app_yaml
}

resource "kubectl_manifest" "sample_app" {
  for_each  = data.kubectl_file_documents.sample_app.manifests
  yaml_body = each.value

  depends_on = [
    null_resource.build_images,
    kubectl_manifest.otel_instrumentation,
    helm_release.ingress_nginx,
    kubectl_manifest.network_policies,
  ]
}
