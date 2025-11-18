variable "stack_name" {
  description = "Name prefix for network resources."
  type        = string
}

resource "civo_network" "network" {
  label = "${var.stack_name}-net"
}

resource "civo_firewall" "firewall" {
  name       = "${var.stack_name}-fw"
  network_id = civo_network.network.id

  create_default_rules = false

  ingress_rule {
    label      = "allow-http"
    protocol   = "tcp"
    port_range = "80"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  ingress_rule {
    label      = "allow-https"
    protocol   = "tcp"
    port_range = "443"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  ingress_rule {
    label      = "allow-ssh"
    protocol   = "tcp"
    port_range = "22"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  ingress_rule {
    label      = "allow-flask"
    protocol   = "tcp"
    port_range = "5000"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  ingress_rule {
    label      = "allow-agent-service"
    protocol   = "tcp"
    port_range = "3000"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  ingress_rule {
    label      = "allow-inngest-dev-ui"
    protocol   = "tcp"
    port_range = "8288"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  ingress_rule {
    label      = "allow-ollama"
    protocol   = "tcp"
    port_range = "11434"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  egress_rule {
    label      = "allow-all-egress"
    protocol   = "tcp"
    port_range = "1-65535"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }
}

output "network_id" {
  value = civo_network.network.id
}

output "firewall_id" {
  value = civo_firewall.firewall.id
}
