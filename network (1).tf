provider "azurerm" {
  features {}

  # subscription_id = "${var.subscriptionId}"
}

resource "azurerm_resource_group" "default" {
  name     = "bug-report-rg"
  location = "West Europe"
}

resource "azurerm_resource_group" "default-AKS" {
  name     = "bug-report-rg-AKS"
  location = "West Europe"
}


resource "azurerm_network_security_group" "default" {
  name                = "bug-report-ag-nsg"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name

  security_rule {
    name                       = "AllowApplicationGatewayInboundTrafficNecessaryPorts"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowApplicationGatewayInboundTrafficPort80"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_virtual_network" "default" {
  name                = "bug-report-vnet"
  address_space       = ["10.240.0.0/12"]
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  subnet {
          address_prefix = "10.240.0.0/16"
          name           = "ag"
          security_group = azurerm_network_security_group.default.id
  }
}

resource "azurerm_role_assignment" "aks-agic-vnet" {
  scope                = lower(azurerm_virtual_network.default.id)
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.default.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

resource "azurerm_role_assignment" "aks-agic-ag-1" {
  scope                = lower(azurerm_application_gateway.default.id)
  role_definition_name = "Contributor"
  principal_id         = azurerm_kubernetes_cluster.default.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

resource "azurerm_role_assignment" "aks-agic-ag-2" {
  scope                = lower(azurerm_application_gateway.default.id)
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.default.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

resource "azurerm_role_assignment" "aks-agic-rg" {
  scope                = lower(azurerm_resource_group.default.id)
  role_definition_name = "Reader"
  principal_id         = azurerm_kubernetes_cluster.default.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

/*data "azurerm_resources" "vnets" {
  resource_group_name = azurerm_kubernetes_cluster.default.node_resource_group
  type                = "Microsoft.Network/virtualNetworks"
}*/

resource "azurerm_virtual_network" "default-AKS" {
  name                = "bug-report-vnet"
  address_space       = ["192.168.1.0/24"]
  location            = azurerm_resource_group.default-AKS.location
  resource_group_name = azurerm_resource_group.default-AKS.name
}  

/*data "azurerm_virtual_network" "aks" {
  name                = data.azurerm_resources.vnets.resources[0].name
  resource_group_name = azurerm_kubernetes_cluster.default.node_resource_group
}*/

resource "azurerm_virtual_network_peering" "aks2ag" {
  name                      = "aks2ag"
  resource_group_name       = azurerm_resource_group.default-AKS.name 
  virtual_network_name      = azurerm_virtual_network.default-AKS.name
  remote_virtual_network_id = azurerm_virtual_network.default.id
}

resource "azurerm_virtual_network_peering" "ag2aks" {
  name                      = "ag2aks"
  resource_group_name       = azurerm_resource_group.default.name
  virtual_network_name      = azurerm_virtual_network.default.name
  remote_virtual_network_id = azurerm_virtual_network.default-AKS.id
}









resource "azurerm_kubernetes_cluster" "default" {
  name                = "bug-report-cluster"
  location            = azurerm_resource_group.default-AKS.location
  resource_group_name = azurerm_resource_group.default-AKS.name
  dns_prefix          = "bug-report-k8s"
  automatic_channel_upgrade = "patch"

  default_node_pool {
    name                = "system"
    # node_count          = 3
    min_count           = "3"
    max_count           = "16"
    vm_size             = "Standard_D12_v2"
    os_disk_size_gb     = 128
    enable_auto_scaling = true
    temporary_name_for_rotation = "temp"
  }

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control_enabled = true

  network_profile {
    # network_plugin = "azure"
    network_plugin = "kubenet"
  }

  ingress_application_gateway {
    gateway_id = azurerm_application_gateway.default.id
  }
}








resource "azurerm_public_ip" "default" {
  name                = "bug-report-pip"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  allocation_method   = "Static"

  sku                 = "Standard"

  tags = {
    environment = "bug-report"
  }
}

locals {
  backend_address_pool_name      = "${azurerm_virtual_network.default.name}-beap"
  frontend_port_name             = "${azurerm_virtual_network.default.name}-feport"
  frontend_ip_configuration_name = "${azurerm_virtual_network.default.name}-feip"
  http_setting_name              = "${azurerm_virtual_network.default.name}-be-htst"
  listener_name                  = "${azurerm_virtual_network.default.name}-httplstn"
  request_routing_rule_name      = "${azurerm_virtual_network.default.name}-rqrt"
  redirect_configuration_name    = "${azurerm_virtual_network.default.name}-rdrcfg"
}

resource "azurerm_application_gateway" "default" {
  name                = "bug-report-appgateway"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 2
    max_capacity = 10
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = tolist(azurerm_virtual_network.default.subnet)[0].id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.default.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    path                  = "/path1/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name

    priority                   = 100
  }

  waf_configuration {
    enabled = false
    firewall_mode = "Prevention"
    rule_set_version = "3.2"
  }
}

