# Testes da validação de ssh_allowed_cidr. Sem credencial da Azure: os providers são simulados (mock) e só
# se roda `plan`. Rodar: terraform test (em terraform/, depois de terraform init -backend=false).

mock_provider "azurerm" {}
mock_provider "random" {}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  location        = "brazilsouth"
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF1VpvPH6a8Pz127uwOwX+zbpCZMjnqdo+X5UZh9w7cu teste@exemplo"
}

run "aceita_1_203_0_113_7_32" {
  command = plan
  variables {
    ssh_allowed_cidr = "203.0.113.7/32"
  }
}

run "aceita_2_203_0_113_0_24" {
  command = plan
  variables {
    ssh_allowed_cidr = "203.0.113.0/24"
  }
}

run "aceita_3_10_0_0_0_25" {
  command = plan
  variables {
    ssh_allowed_cidr = "10.0.0.0/25"
  }
}

run "recusa_1_0_0_0_0_0" {
  command = plan
  variables {
    ssh_allowed_cidr = "0.0.0.0/0"
  }
  expect_failures = [var.ssh_allowed_cidr]
}

run "recusa_2_0_0_0_0_1" {
  command = plan
  variables {
    ssh_allowed_cidr = "0.0.0.0/1"
  }
  expect_failures = [var.ssh_allowed_cidr]
}

run "recusa_3_1_2_3_4_0" {
  command = plan
  variables {
    ssh_allowed_cidr = "1.2.3.4/0"
  }
  expect_failures = [var.ssh_allowed_cidr]
}

run "recusa_4_10_0_0_0_8" {
  command = plan
  variables {
    ssh_allowed_cidr = "10.0.0.0/8"
  }
  expect_failures = [var.ssh_allowed_cidr]
}

run "recusa_5_cc_0" {
  command = plan
  variables {
    ssh_allowed_cidr = "::/0"
  }
  expect_failures = [var.ssh_allowed_cidr]
}

run "recusa_6_2001cdb8cc_32" {
  command = plan
  variables {
    ssh_allowed_cidr = "2001:db8::/32"
  }
  expect_failures = [var.ssh_allowed_cidr]
}

run "recusa_7_1_2_3_4" {
  command = plan
  variables {
    ssh_allowed_cidr = "1.2.3.4"
  }
  expect_failures = [var.ssh_allowed_cidr]
}

run "recusa_8_1_2_3_4_33" {
  command = plan
  variables {
    ssh_allowed_cidr = "1.2.3.4/33"
  }
  expect_failures = [var.ssh_allowed_cidr]
}

run "recusa_9_300_1_1_1_32" {
  command = plan
  variables {
    ssh_allowed_cidr = "300.1.1.1/32"
  }
  expect_failures = [var.ssh_allowed_cidr]
}

run "recusa_10_asterisco" {
  command = plan
  variables {
    ssh_allowed_cidr = "*"
  }
  expect_failures = [var.ssh_allowed_cidr]
}

run "recusa_11_Internet" {
  command = plan
  variables {
    ssh_allowed_cidr = "Internet"
  }
  expect_failures = [var.ssh_allowed_cidr]
}
