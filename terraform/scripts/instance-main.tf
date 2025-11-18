resource "civo_instance" "agent_app" {
  hostname = "${var.stack_name}-agent"
  size     = var.instance_size
  region   = var.region

  # Ubuntu 22.04 LTS
  disk_image = var.disk_image

  # Network and firewall
  network_id  = var.network_id
  firewall_id = var.firewall_id

  # SSH key
  sshkey_id = var.ssh_key_id

  # Startup script with environment variables
  script = templatefile("${path.module}/../scripts/startup.sh", {
    DOCKER_IMAGE        = "${var.image_repo}:${var.image_tag}"
    OLLAMA_MODEL        = var.ollama_model
    INNGEST_APP_ID      = var.inngest_app_id
    AGENT_RESULT_TOKEN  = var.agent_result_token
  })

  tags = [
    "agent-app",
    var.stack_name,
    "terraform"
  ]
}

# Output the public IP
output "public_ip" {
  value       = civo_instance.agent_app.public_ip
  description = "Public IP address of the agent app instance"
}

output "instance_id" {
  value       = civo_instance.agent_app.id
  description = "Instance ID"
}

output "frontend_url" {
  value       = "http://${civo_instance.agent_app.public_ip}:5000"
  description = "Frontend URL"
}

output "inngest_dev_ui" {
  value       = "http://${civo_instance.agent_app.public_ip}:8288"
  description = "Inngest Dev UI URL"
}
