# Uma VM com K3s (mesmo Kubernetes do k3d local) atrás de um firewall que só deixa entrar 80 e 443.
#
#   internet --80/443--> IP público estático --> NSG --> VM (K3s: Traefik, ArgoCD, app, observabilidade)
#   você ------22------> (só do seu IP) ----------------> SSH (e túnel para a API do Kubernetes)

resource "random_string" "dns" {
  length  = 5
  upper   = false
  special = false
}

locals {
  # Nome DNS gratuito da própria Azure no IP público: serve de endereço da aplicação e permite
  # Let's Encrypt (HTTP-01) sem comprar domínio.
  dns_label = "${var.name_prefix}-${random_string.dns.result}"
  fqdn      = "${local.dns_label}.${var.location}.cloudapp.azure.com"
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.20.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  name                 = "${var.name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_public_ip" "this" {
  name                = "${var.name_prefix}-ip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  # Estático: o IP não muda quando a VM é desligada e ligada (o DNS e o Let's Encrypt dependem disso).
  allocation_method = "Static"
  sku               = "Standard"
  domain_name_label = local.dns_label
  tags              = var.tags
}

resource "azurerm_network_security_group" "this" {
  #checkov:skip=CKV_AZURE_160:porta 80 aberta de propósito: desafio HTTP-01 do Let's Encrypt e redirect para HTTPS
  name                = "${var.name_prefix}-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  # Tudo que não está listado aqui é negado (regra padrão de entrada da Azure). Em especial NÃO há regra para
  # 6443 (API do Kubernetes), 8081 (Actuator), 9090 e 3000 (Prometheus e Grafana) nem 30000+ (NodePort).
  security_rule {
    name                       = "ssh-do-meu-ip"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.ssh_allowed_cidr
    destination_address_prefix = "*"
  }

  # http e https abertos ao mundo é o ponto: a aplicação é pública. Já o SSH (acima) só aceita o seu IP.
  #trivy:ignore:AZU-0047
  security_rule {
    name                       = "http"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  #trivy:ignore:AZU-0047
  security_rule {
    name                       = "https"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Dois achados do scanner, ambos justificados:
#  - AZU-0076 (IP público na NIC): é uma VM única, sem balanceador na frente. O NSG da sub-rede limita o que chega
#    nele a 80, 443 e ao SSH do seu IP.
#  - AZU-0068 (NIC sem NSG): falso positivo. O NSG ESTÁ associado, mas à sub-rede
#    (azurerm_subnet_network_security_group_association), recurso que o scanner não segue.
#trivy:ignore:AZU-0076
#trivy:ignore:AZU-0068
resource "azurerm_network_interface" "this" {
  #checkov:skip=CKV_AZURE_119:VM única sem balanceador na frente; o NSG da sub-rede limita o que chega
  name                = "${var.name_prefix}-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  ip_configuration {
    name                          = "interno"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }

  # Sem isto o Terraform pode criar a NIC (e a VM, com IP público) ANTES de o firewall estar ligado à sub-rede:
  # nada no grafo ligava os dois. A VM nunca pode existir sem o NSG.
  depends_on = [azurerm_subnet_network_security_group_association.this]
}

# NSG na SUB-REDE (e não só na placa de rede): qualquer VM que entrar aqui no futuro já nasce protegida.
resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_linux_virtual_machine" "this" {
  #checkov:skip=CKV_AZURE_50:extensões necessárias para o `az vm user update` (recuperar o acesso SSH)
  name                = "${var.name_prefix}-vm"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  size                = var.vm_size
  admin_username      = var.admin_username
  tags                = var.tags

  network_interface_ids = [azurerm_network_interface.this.id]

  # Só chave SSH. Sem senha.
  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Storage gerenciado pela Azure: dá acesso ao log serial/console se o cloud-init falhar e o SSH não subir.
  boot_diagnostics {}

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    k3s_version = var.k3s_version
    fqdn        = local.fqdn
  }))

  lifecycle {
    # `latest` da imagem muda com o tempo, e o cloud-init só roda no primeiro boot: trocar a VM por isso
    # apagaria o cluster (e o banco).
    ignore_changes = [source_image_reference, custom_data]
  }
}

# Desliga a VM todo dia: o crédito estudantil é limitado e uma VM esquecida ligada o consome.
resource "azurerm_dev_test_global_vm_shutdown_schedule" "this" {
  count = var.auto_shutdown_enabled ? 1 : 0

  virtual_machine_id    = azurerm_linux_virtual_machine.this.id
  location              = azurerm_resource_group.this.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone

  notification_settings {
    enabled = false
  }
  tags = var.tags
}
