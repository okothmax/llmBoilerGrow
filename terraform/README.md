# Civo Compute Instance Deployment

This Terraform configuration deploys the LLM Agent application to a Civo compute instance with:

- **Docker** running your application container
- **Ollama** for local LLM inference
- **Inngest Dev Server** for function orchestration
- **Systemd services** for automatic startup and restart

## Architecture

```
┌─────────────────────────────────────────┐
│   Civo Compute Instance (Ubuntu 22.04)  │
├─────────────────────────────────────────┤
│                                          │
│  ┌──────────────────────────────────┐   │
│  │  Ollama Service (port 11434)     │   │
│  │  Model: llama3.2:3b              │   │
│  └──────────────────────────────────┘   │
│                                          │
│  ┌──────────────────────────────────┐   │
│  │  Inngest Dev Server (port 8288)  │   │
│  │  Function orchestration UI       │   │
│  └──────────────────────────────────┘   │
│                                          │
│  ┌──────────────────────────────────┐   │
│  │  Docker Container (host network) │   │
│  │  - Flask API (port 5000)         │   │
│  │  - Agent Service (port 3000)     │   │
│  └──────────────────────────────────┘   │
│                                          │
└─────────────────────────────────────────┘
```

## Prerequisites

1. **Civo API Token**: Get from https://dashboard.civo.com/security
2. **SSH Key**: Default uses `~/.ssh/id_rsa.pub` or specify via variable
3. **Terraform**: v1.0+

## Quick Start

### 1. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
civo_token = "your-civo-api-token"
region     = "LON1"
stack_name = "llm-agent-compute"

# Optional overrides
agent_result_token = "your-secret-token"
```

### 2. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 3. Access Your Application

After deployment completes (5-10 minutes), Terraform will output:

```
Outputs:

frontend_url = "http://X.X.X.X:5000"
inngest_dev_ui = "http://X.X.X.X:8288"
ssh_command = "ssh root@X.X.X.X"
```

- **Frontend**: Test the agent via web UI
- **Inngest Dev UI**: Monitor function runs and debug
- **SSH**: Access the instance for logs and debugging

## Testing

### Via Frontend

1. Open `http://<PUBLIC_IP>:5000` in your browser
2. Enter a prompt like "What is the current date and time in London?"
3. Watch the status update as the agent processes your request

### Via API

```bash
# Submit request
curl -X POST http://<PUBLIC_IP>:5000/api/agent \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Summarise the benefits of data sovereignty."}'

# Response: {"request_id":"abc123...","status":"processing"}

# Poll for result
curl http://<PUBLIC_IP>:5000/api/agent/abc123...
```

## Monitoring

### Check Service Status

```bash
ssh root@<PUBLIC_IP>

# Check all services
systemctl status ollama
systemctl status inngest-dev
systemctl status agent-app

# View logs
journalctl -u agent-app -f
journalctl -u inngest-dev -f
journalctl -u ollama -f

# View startup script logs
tail -f /var/log/startup.log
```

### Inngest Dev UI

Open `http://<PUBLIC_IP>:8288` to see:
- Function runs in real-time
- Tool calls and LLM interactions
- Errors and retry attempts

## Configuration

### Environment Variables

All configuration is done via Terraform variables. The startup script passes these to the services:

| Variable | Default | Description |
|----------|---------|-------------|
| `civo_token` | - | **Required** Civo API token |
| `region` | `LON1` | Civo region |
| `stack_name` | `llm-agent-compute` | Resource name prefix |
| `instance_size` | `g4s.kube.medium` | Instance size |
| `ssh_public_key` | `~/.ssh/id_rsa.pub` | SSH public key |
| `image_repo` | `okothmax/llm-boilerplate-app` | Docker image |
| `image_tag` | `latest` | Docker image tag |
| `ollama_model` | `llama3.2:3b` | Ollama model to pull |
| `inngest_app_id` | `civo-agent` | Inngest app identifier |
| `agent_result_token` | `change-me-in-production` | Secret callback token |

### Firewall Rules

The deployment automatically opens:

- **22** - SSH
- **80** - HTTP
- **443** - HTTPS
- **3000** - Agent service (Inngest callbacks)
- **5000** - Flask frontend/API
- **8288** - Inngest Dev UI
- **11434** - Ollama API

## Troubleshooting

### Instance not responding

```bash
# Check if services started
ssh root@<PUBLIC_IP>
systemctl status agent-app
journalctl -u agent-app -n 50
```

### Ollama model not loaded

```bash
ssh root@<PUBLIC_IP>
ollama list
ollama pull llama3.2:3b
systemctl restart agent-app
```

### Inngest function not registering

```bash
# Check Inngest dev server
systemctl status inngest-dev
journalctl -u inngest-dev -f

# Restart services
systemctl restart inngest-dev
systemctl restart agent-app
```

### Docker container failing

```bash
# View container logs
docker logs agent-app

# Restart container
systemctl restart agent-app
```

## Cleanup

```bash
terraform destroy
```

This will remove:
- Compute instance
- Network and firewall
- SSH key

## Cost Estimate

- **g4s.kube.medium**: ~$0.05/hour (~$36/month)
- **Network**: Free
- **Firewall**: Free

## Next Steps

1. **Production Setup**: Replace Inngest Dev Server with Inngest Cloud keys
2. **HTTPS**: Add Caddy/Nginx reverse proxy with Let's Encrypt
3. **Monitoring**: Add Prometheus/Grafana
4. **Scaling**: Use Kubernetes deployment from `infra/tf/` for multi-node setup

## Files

- `main.tf` - Main configuration
- `variables.tf` - Variable definitions
- `terraform.tfvars.example` - Example configuration
- `scripts/startup.sh` - Instance initialization script
- `scripts/instance-main.tf` - Instance module
- `scripts/instance-variables.tf` - Instance module variables
- `modules/network/` - Network and firewall module
