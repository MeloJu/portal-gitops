output "fqdn" {
  description = "Endereço público da aplicação (DNS gratuito da Azure no IP estático)."
  value       = local.fqdn
}

output "public_ip" {
  description = "IP público estático."
  value       = azurerm_public_ip.this.ip_address
}

output "ssh" {
  description = "Comando para entrar na VM."
  value       = "ssh ${var.admin_username}@${local.fqdn}"
}

output "kubectl_tunnel" {
  description = "Túnel SSH para usar o kubectl da sua máquina (a 6443 não é exposta na internet)."
  value       = "ssh -N -L 6443:127.0.0.1:6443 ${var.admin_username}@${local.fqdn}"
}

output "kubeconfig_comando" {
  description = "Copia o kubeconfig do K3s da VM (aponta para 127.0.0.1:6443, que o túnel acima atende)."
  value       = "(umask 077; ssh ${var.admin_username}@${local.fqdn} 'sudo cat /etc/rancher/k3s/k3s.yaml' > kubeconfig-azure.yaml)"
}

output "parar_vm" {
  description = "Desliga a VM (deallocate): para de cobrar CPU e RAM. Disco e IP continuam cobrando centavos."
  value       = "az vm deallocate -g ${azurerm_resource_group.this.name} -n ${azurerm_linux_virtual_machine.this.name}"
}

output "ligar_vm" {
  description = "Liga a VM de novo (o K3s e o ArgoCD sobem sozinhos)."
  value       = "az vm start -g ${azurerm_resource_group.this.name} -n ${azurerm_linux_virtual_machine.this.name}"
}
