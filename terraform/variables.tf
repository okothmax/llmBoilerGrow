variable "civo_token" {
  description = "Civo API token."
  type        = string
}

variable "region" {
  description = "Civo region to deploy into (e.g. LON1)."
  type        = string
  default     = "LON1"
}

variable "stack_name" {
  description = "Name prefix for this compute stack."
  type        = string
  default     = "llm-agent-compute"
}

variable "image_repo" {
  description = "Docker image repository for the app."
  type        = string
  default     = "okothmax/llm-boilerplate-app"
}

variable "image_tag" {
  description = "Docker image tag for the app."
  type        = string
  default     = "latest"
}

variable "ssh_public_key" {
  description = "SSH public key for instance access."
  type        = string
  default     = ""
}

variable "instance_size" {
  description = "Civo instance size."
  type        = string
  default     = "g4s.large"
}

variable "ollama_model" {
  description = "Ollama model to pull on startup."
  type        = string
  default     = "llama3.2:3b"
}

variable "inngest_app_id" {
  description = "Inngest application ID."
  type        = string
  default     = "civo-agent"
}

variable "agent_result_token" {
  description = "Secret token for agent result callbacks."
  type        = string
  sensitive   = true
  default     = "change-me-in-production"
}
