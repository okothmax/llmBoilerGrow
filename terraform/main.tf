terraform {
  required_providers {
    civo = {
      source  = "civo/civo"
      version = "1.1.2"
    }
  }
}

provider "civo" {
  token  = var.civo_token
  region = var.region
}

module "network" {
  source     = "./modules/network"
  stack_name = var.stack_name
}

# SSH key for instance access
resource "civo_ssh_key" "agent_key" {
  name       = "${var.stack_name}-key"
  public_key = var.ssh_public_key != "" ? var.ssh_public_key : file(pathexpand("~/.ssh/id_rsa.pub"))
}

module "instance" {
  source             = "./scripts"
  stack_name         = var.stack_name
  region             = var.region
  instance_size      = var.instance_size
  network_id         = module.network.network_id
  firewall_id        = module.network.firewall_id
  ssh_key_id         = civo_ssh_key.agent_key.id
  image_repo         = var.image_repo
  image_tag          = var.image_tag
  ollama_model       = var.ollama_model
  inngest_app_id     = var.inngest_app_id
  agent_result_token = var.agent_result_token
}

output "app_public_ip" {
  description = "Public IP address of the compute instance running the app."
  value       = module.instance.public_ip
}

output "frontend_url" {
  description = "Frontend application URL"
  value       = module.instance.frontend_url
}

output "inngest_dev_ui" {
  description = "Inngest Dev UI URL"
  value       = module.instance.inngest_dev_ui
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh root@${module.instance.public_ip}"
}
