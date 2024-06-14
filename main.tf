terraform {
  backend "azurerm" {
  }
}

provider "azurerm" {
  version = ">=3.33.0"
  # The "feature" block is required for AzureRM provider 2.xx.
  features {}
  subscription_id = var.AZURE_SUBSCRIPTION_ID
  tenant_id       = var.AZURE_AD_TENANT_ID
  client_id       = var.AZURE_AD_CLIENT_ID
  client_secret   = var.AZURE_AD_CLIENT_SECRET
}

variable "prefix" {
  default = "tfvmultra"
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-resources"
  location = "East US"
}

resource "azurerm_sql_server" "prjsql" {
  name                         = "${var.prefix}-sqlserver"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "var.ADMIN_USERNAME"
  administrator_login_password = "var.ADMIN_PASSWORD"

  tags = {
    environment = "staging"
  }
}

resource "azurerm_storage_account" "sg" {
  name                     = "${var.prefix}storage"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "cont" {
  name                  = "${var.prefix}-container"
  storage_account_name  = azurerm_storage_account.sg.name
  container_access_type = "private"
}

resource "azurerm_storage_queue" "que" {
  name                 = "${var.prefix}-queue"
  storage_account_name = azurerm_storage_account.sg.name
}

resource "azurerm_sql_database" "ultragenyxsqldb" {
  name                = "ultragenyx"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  server_name         = azurerm_sql_server.ultragensql.name
  
  tags = {
    environment = "staging"
  }
}

resource "azurerm_mssql_server_extended_auditing_policy" "sqlDbServerAuditingPolicy" {
  server_id                               = azurerm_sql_server.ultragensql.id
  storage_endpoint                        = azurerm_storage_account.sg.primary_blob_endpoint
  storage_account_access_key              = azurerm_storage_account.sg.primary_access_key
  storage_account_access_key_is_secondary = true
  retention_in_days                       = 7
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_public_ip" "ultragenip" {
  name                = "${var.prefix}-public-ip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Dynamic" 
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_interface" "main" {
  name                = "${var.prefix}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.ultragenip.id
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "ssh_nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow_ssh_sg"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
   security_rule {
    name                       = "allow_http_sg"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
   security_rule {
    name                       = "allow_https_sg"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
   security_rule {
    name                       = "allow_app_sg"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "association" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_virtual_machine" "main" {
  name                  = "${var.prefix}-vm"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.main.id]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  # delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  # delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "var.USERNAME"
    admin_username = "var.ADMIN_USERNAME"
    admin_password = "var.ADMIN_PASSWORD"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "staging"
  }
}
