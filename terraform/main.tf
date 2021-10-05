terraform {
  backend "local" {
    path = "./state/terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "bdcc" {
  name     = "rg-${var.ENV}-${var.LOCATION}"
  location = var.LOCATION

  lifecycle {
    prevent_destroy = false
  }

  tags = {
    region = var.BDCC_REGION
    env    = var.ENV
  }
}

resource "azurerm_storage_account" "bdcc" {
  depends_on = [
    azurerm_resource_group.bdcc
  ]

  name                     = "st${var.ENV}${var.LOCATION}"
  resource_group_name      = azurerm_resource_group.bdcc.name
  location                 = azurerm_resource_group.bdcc.location
  account_tier             = "Standard"
  account_replication_type = var.STORAGE_ACCOUNT_REPLICATION_TYPE
  is_hns_enabled           = "true"

  network_rules {
    default_action = "Allow"
    ip_rules       = values(var.IP_RULES)
  }

  lifecycle {
    prevent_destroy = false
  }

  tags = {
    region = var.BDCC_REGION
    env    = var.ENV
  }
}

resource "azurerm_storage_container" "data_container" {
  depends_on = [
    azurerm_storage_account.bdcc
  ]

  name                  = "data"
  storage_account_name  = azurerm_storage_account.bdcc.name
  container_access_type = "private"

  lifecycle {
    prevent_destroy = false
  }
}

resource "azurerm_container_registry" "bdcc" {
  name                = "cr${var.ENV}${var.LOCATION}"
  resource_group_name = azurerm_resource_group.bdcc.name
  location            = azurerm_resource_group.bdcc.location
  sku                 = "Basic"
  admin_enabled       = false

}

resource "azurerm_kubernetes_cluster" "bdcc" {
  depends_on = [
    azurerm_resource_group.bdcc
  ]

  name                = "aks-${var.ENV}-${var.LOCATION}"
  location            = azurerm_resource_group.bdcc.location
  resource_group_name = azurerm_resource_group.bdcc.name
  dns_prefix          = "bdcc${var.ENV}"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    region = var.BDCC_REGION
    env    = var.ENV
  }
}

resource "azurerm_role_assignment" "role_acrpull" {
  depends_on = [
    azurerm_container_registry.bdcc,
    azurerm_kubernetes_cluster.bdcc
  ]

  scope                            = azurerm_container_registry.bdcc.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.bdcc.kubelet_identity.0.object_id
  skip_service_principal_aad_check = true
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.bdcc.kube_config.0.client_certificate
  sensitive = true
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.bdcc.kube_config_raw
  sensitive = true
}
