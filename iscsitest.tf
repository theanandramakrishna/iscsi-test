provider azurerm {}

variable "location" {
  default = "westus2"
}

variable "vmsize" {
  default = "Standard_D3_v2"
}

resource azurerm_resource_group "iscsitest" {
  name     = "iscsitest"
  location = "${var.location}"

  tags {
    workload = "iscsitest"
  }
}

resource azurerm_virtual_network "iscsitest" {
  name                = "iscsitest_vnet"
  location            = "${azurerm_resource_group.iscsitest.location}"
  resource_group_name = "${azurerm_resource_group.iscsitest.name}"
  address_space       = ["10.0.0.0/16"]
}

resource azurerm_network_security_group "iscsitest" {
  name                = "iscsitest_nsg"
  location            = "${azurerm_resource_group.iscsitest.location}"
  resource_group_name = "${azurerm_resource_group.iscsitest.name}"

  security_rule {
    name                       = "iscsitest_nsg_allow_rule"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "71.231.179.163"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "iscsitest_nsg_allow_vnet_rule"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "iscsitest_nsg_allow_lb_rule"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "iscsitest_nsg_deny_rule"
    priority                   = 3000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource azurerm_subnet "iscsitest" {
  name                      = "iscsitest_subnet"
  resource_group_name       = "${azurerm_resource_group.iscsitest.name}"
  virtual_network_name      = "${azurerm_virtual_network.iscsitest.name}"
  address_prefix            = "10.0.1.0/24"
  network_security_group_id = "${azurerm_network_security_group.iscsitest.id}"
}

resource azurerm_public_ip "bastion_pip" {
  name                         = "bastion_pip"
  location                     = "${azurerm_resource_group.iscsitest.location}"
  resource_group_name          = "${azurerm_resource_group.iscsitest.name}"
  public_ip_address_allocation = "Dynamic"
  idle_timeout_in_minutes      = 30
  domain_name_label            = "iscsibastion"
}

locals {
  bastion_fqdn                 = "${azurerm_public_ip.bastion_pip.fqdn}"
  bastion_user_name            = "bastionuser"
  scsi_initiator_computer_name = "scsiinitiator"
  scsi_initiator_user_name     = "scsiinit"
  scsi_target_computer_name    = "scsitarget"
  scsi_target_user_name        = "scsitarget"
}

resource azurerm_network_interface "bastion_nic" {
  name                = "bastion_nic"
  resource_group_name = "${azurerm_resource_group.iscsitest.name}"
  location            = "${azurerm_resource_group.iscsitest.location}"

  ip_configuration {
    name                          = "bastion_nic_ipconfig"
    subnet_id                     = "${azurerm_subnet.iscsitest.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.bastion_pip.id}"
  }
}

resource azurerm_network_interface "iscsitest_initiator_nic" {
  name                          = "iscsitest_initiator_nic"
  resource_group_name           = "${azurerm_resource_group.iscsitest.name}"
  location                      = "${azurerm_resource_group.iscsitest.location}"
  enable_accelerated_networking = true

  ip_configuration {
    name                          = "iscsitest_initiator_nic_ipconfig"
    subnet_id                     = "${azurerm_subnet.iscsitest.id}"
    private_ip_address_allocation = "dynamic"
  }
}

resource azurerm_network_interface "iscsitest_target_nic" {
  name                          = "iscsitest_target_nic"
  resource_group_name           = "${azurerm_resource_group.iscsitest.name}"
  location                      = "${azurerm_resource_group.iscsitest.location}"
  enable_accelerated_networking = true

  ip_configuration {
    name                          = "iscsitest_target_nic_ipconfig"
    subnet_id                     = "${azurerm_subnet.iscsitest.id}"
    private_ip_address_allocation = "dynamic"
  }
}

resource azurerm_storage_account "iscsitest_diagnostics" {
  name                     = "iscsitest"
  resource_group_name      = "${azurerm_resource_group.iscsitest.name}"
  location                 = "${azurerm_resource_group.iscsitest.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource tls_private_key "bastion_key_pair" {
  algorithm = "RSA"
}

resource azurerm_virtual_machine "bastion_vm" {
  name                          = "bastion"
  location                      = "${azurerm_resource_group.iscsitest.location}"
  resource_group_name           = "${azurerm_resource_group.iscsitest.name}"
  delete_os_disk_on_termination = true
  vm_size                       = "Standard_A1_v2"
  network_interface_ids         = ["${azurerm_network_interface.bastion_nic.id}"]

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "os_disk_bastion"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "bastion"
    admin_username = "${local.bastion_user_name}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys = [{
      path     = "/home/${local.bastion_user_name}/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/azureid_rsa.pub")}"
    }]
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = "${azurerm_storage_account.iscsitest_diagnostics.primary_blob_endpoint}"
  }
}

resource azurerm_virtual_machine "iscsitest_initiator_vm" {
  name                          = "iscsitest_initiator"
  location                      = "${azurerm_resource_group.iscsitest.location}"
  resource_group_name           = "${azurerm_resource_group.iscsitest.name}"
  delete_os_disk_on_termination = true
  vm_size                       = "${var.vmsize}"
  network_interface_ids         = ["${azurerm_network_interface.iscsitest_initiator_nic.id}"]

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "os_disk_initiator"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${local.scsi_initiator_computer_name}"
    admin_username = "${local.scsi_initiator_user_name}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys = [{
      path     = "/home/${local.scsi_initiator_user_name}/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/azureid_rsa.pub")}"
    }]
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = "${azurerm_storage_account.iscsitest_diagnostics.primary_blob_endpoint}"
  }
}

resource azurerm_virtual_machine "iscsitest_target_vm" {
  name                          = "iscsitest_target"
  location                      = "${azurerm_resource_group.iscsitest.location}"
  resource_group_name           = "${azurerm_resource_group.iscsitest.name}"
  delete_os_disk_on_termination = true
  vm_size                       = "${var.vmsize}"
  network_interface_ids         = ["${azurerm_network_interface.iscsitest_target_nic.id}"]

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "os_disk_target"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_data_disk {
    name          = "data_disk_1"
    caching       = "ReadOnly"
    create_option = "Empty"
    lun           = 0
    disk_size_gb  = 1024
  }

  os_profile {
    computer_name  = "${local.scsi_target_computer_name}"
    admin_username = "${local.scsi_target_user_name}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys = [{
      path     = "/home/${local.scsi_target_user_name}/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/azureid_rsa.pub")}"
    }]
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = "${azurerm_storage_account.iscsitest_diagnostics.primary_blob_endpoint}"
  }
}

output "bastionfqdn" {
  //value = "${azurerm_public_ip.bastion_pip.domain_name_label}.${var.location}.cloudapp.azure.com"
  value = "${local.bastion_fqdn}"
}
