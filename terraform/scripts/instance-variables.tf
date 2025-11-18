variable "stack_name" {
  description = "Name prefix for resources"
  type        = string
}

variable "region" {
  description = "Civo region"
  type        = string
}

variable "instance_size" {
  description = "Instance size (e.g., g4s.large)"
  type        = string
  default     = "g4s.large"
}

variable "disk_image" {
  description = "Disk image ID for Ubuntu 22.04"
  type        = string
  default     = "eda67ea0-4282-4945-9b7b-d3e1cba1d987"
}

variable "network_id" {
  description = "Network ID"
  type        = string
}

variable "firewall_id" {
  description = "Firewall ID"
  type        = string
}

variable "ssh_key_id" {
  description = "SSH key ID"
  type        = string
}

variable "image_repo" {
  description = "Docker image repository"
  type        = string
  default     = "okothmax/llm-boilerplate-app"
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
}

variable "ollama_model" {
  description = "Ollama model to pull"
  type        = string
  default     = "llama3.2:3b"
}

variable "inngest_app_id" {
  description = "Inngest app ID"
  type        = string
  default     = "civo-agent"
}

variable "agent_result_token" {
  description = "Agent result callback token"
  type        = string
  sensitive   = true
}
