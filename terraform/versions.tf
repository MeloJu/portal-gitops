terraform {
  required_version = ">= 1.9"

  required_providers {
    # 4.x fixada de propósito: a 5.x (já lançada) muda o schema de vários recursos. Migrar é uma task à parte,
    # com `terraform plan` limpo antes e depois.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
