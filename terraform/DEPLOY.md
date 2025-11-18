# Quick Deployment Guide

## 1. Setup (One-time)

```bash
cd ~/Desktop/<>/Developer/_llmBoilerGrow2025/terraform

# Copy example config
cp terraform.tfvars.example terraform.tfvars

# Edit with your Civo token
nano terraform.tfvars
```

Required in `terraform.tfvars`:
```hcl
civo_token = "your-actual-civo-api-token-here"
```

## 2. Deploy

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy (takes 5-10 minutes)
terraform apply
```

Type `yes` when prompted.

## 3. Get Access URLs

After deployment, Terraform outputs:

```
Outputs:

app_public_ip = "X.X.X.X"
frontend_url = "http://X.X.X.X:5000"
inngest_dev_ui = "http://X.X.X.X:8288"
ssh_command = "ssh root@X.X.X.X"
```

## 4. Test

### Option A: Web UI
1. Open `frontend_url` in browser
2. Enter prompt: "What is the current date and time in London?"
3. Watch it process

### Option B: API
```bash
# Replace X.X.X.X with your IP
curl -X POST http://X.X.X.X:5000/api/agent \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Tell me about data sovereignty"}'
```

## 5. Monitor

- **Inngest UI**: Open `inngest_dev_ui` to see function runs
- **Logs**: SSH to instance and run `journalctl -u agent-app -f`

## 6. Cleanup

```bash
terraform destroy
```

Type `yes` when prompted.

---

## Common Issues

### "Error: Invalid SSH key"
- Make sure `~/.ssh/id_rsa.pub` exists
- Or set `ssh_public_key` in `terraform.tfvars`

### "Services not starting"
SSH to instance and check:
```bash
tail -f /var/log/startup.log
systemctl status agent-app
```

### "Ollama model not found"
The startup script pulls `llama3.2:3b` automatically. If it fails:
```bash
ssh root@<IP>
ollama pull llama3.2:3b
systemctl restart agent-app
```
