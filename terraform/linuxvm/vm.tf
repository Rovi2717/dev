provider "azurerm" {
  features {}

  subscription_id = "d3ff1e97-d9a9-45ac-9d74-ab34dcae6659"
  client_id       = "4d12569b-5700-44ec-8061-cbf6767d502c"
  client_secret   = "Bao8Q~zXAMqzAf-OtN9a5K1Fy2w6Nplg_t2Pkc6S"
  tenant_id       = "e0cd89e2-e12a-4dd8-8ee8-2efb3946dc4f"
}

resource "azurerm_resource_group" "example" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

resource "azurerm_virtual_network" "example" {
  name                = var.virtual_network_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_subnet" "example" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "example" {
  count = var.number_of_vms
  name                = "pip-${count.index}"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "example" {
  name                = var.network_security_group_name
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "example" {
  count = var.number_of_vms
  name                = "nic-${count.index}"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.example.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.example.*.id[count.index]
  }
}

resource "azurerm_network_interface_security_group_association" "association" {
  count = var.number_of_vms
  network_interface_id      = azurerm_network_interface.example.*.id[count.index]
  network_security_group_id = azurerm_network_security_group.example.id
}

resource "tls_private_key" "example_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "example" {
  count = var.number_of_vms
  name                = "vm-${count.index}"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  size                = "Standard_F2"
  admin_username      = var.username
  network_interface_ids = [
    azurerm_network_interface.example.*.id[count.index],
  ]

  admin_ssh_key {
    username   = var.username
    public_key = tls_private_key.example_ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = "echo ${azurerm_public_ip.example.*.ip_address[count.index]} >> inventory"
  }
}

resource "local_file" "mypem" {
    filename = "mykey.pem"
    content = tls_private_key.example_ssh.private_key_pem
}
