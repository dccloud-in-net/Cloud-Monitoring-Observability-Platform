# Remote state backend.
#
# This file is intentionally minimal — pass values at `terraform init` time
# so the same code works for local dev (no backend block) and CI (remote).
#
# Example:
#   terraform init \
#     -backend-config="resource_group_name=tfstate-rg" \
#     -backend-config="storage_account_name=tfstateobsplat" \
#     -backend-config="container_name=tfstate" \
#     -backend-config="key=cloud-obs-platform.tfstate"
#
# Remove the comment block below to enable remote state.

# terraform {
#   backend "azurerm" {}
# }
