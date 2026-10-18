variable "subscription_id" {
  description = "ID da assinatura Azure (az account show --query id -o tsv)."
  type        = string
}

variable "location" {
  description = <<-EOT
    Região da Azure. No plano estudantil uma Azure Policy limita as regiões permitidas: confira com
    `az policy assignment list` (ver terraform/README.md) e use uma delas. brazilsouth é a mais próxima.
  EOT
  type        = string
  default     = "brazilsouth"
}

variable "vm_size" {
  description = "Tamanho da VM. B2ms = 2 vCPU / 8 GB, o mínimo confortável para K3s + ArgoCD + observabilidade (~4,1 GB em uso)."
  type        = string
  default     = "Standard_B2ms"
}

variable "name_prefix" {
  description = "Prefixo dos recursos."
  type        = string
  default     = "l2"
}

variable "admin_username" {
  description = "Usuário administrador da VM (login só por chave SSH)."
  type        = string
  default     = "lumi"
}

variable "ssh_public_key" {
  description = "Chave SSH PÚBLICA (conteúdo do .pub). A privada nunca sai da sua máquina."
  type        = string

  validation {
    condition     = can(regex("^ssh-(ed25519|rsa) ", var.ssh_public_key))
    error_message = "Use o conteúdo de uma chave pública SSH (começa com ssh-ed25519 ou ssh-rsa)."
  }
}

variable "ssh_allowed_cidr" {
  description = <<-EOT
    De onde o SSH (porta 22) é aceito, em CIDR IPv4. SEM valor padrão de propósito: a porta 22 aberta ao mundo
    leva milhares de tentativas por dia. Use o seu IP, no formato IP/32. Lista de aceitos: só /24 a /32.
  EOT
  type        = string

  validation {
    condition = (
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/(2[4-9]|3[0-2])$", var.ssh_allowed_cidr)) &&
      can(cidrnetmask(var.ssh_allowed_cidr))
    )
    error_message = "Informe um CIDR IPv4 de /24 a /32 (ex.: 203.0.113.7/32). Redes maiores, 0.0.0.0/0 e IPv6 são recusados."
  }
}

variable "os_disk_size_gb" {
  description = "Disco do SO (Standard SSD). Imagens + 3 volumes de 2 Gi cabem folgado em 64."
  type        = number
  default     = 64
}

variable "k3s_version" {
  description = "Versão do K3s, a mesma do k3d local, para o ambiente se comportar igual."
  type        = string
  default     = "v1.35.5+k3s1"
}

variable "auto_shutdown_enabled" {
  description = "Desliga a VM todo dia no horário abaixo. Protege o crédito estudantil de uma VM esquecida ligada."
  type        = bool
  default     = true
}

variable "auto_shutdown_time" {
  description = "Horário do desligamento diário, HHMM (24h), no fuso abaixo."
  type        = string
  default     = "2300"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3])[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "Use HHMM, por exemplo 2300."
  }
}

variable "auto_shutdown_timezone" {
  description = "Fuso do desligamento (nomes do Windows). Brasília = E. South America Standard Time."
  type        = string
  default     = "E. South America Standard Time"
}

variable "tags" {
  description = "Tags nos recursos."
  type        = map(string)
  default = {
    projeto  = "lumi-links"
    ambiente = "azure"
    gerencia = "terraform"
  }
}
