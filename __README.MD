# Civo LLM Boilerplate – Run Book

This document explains how to configure the asynchronous Flask + AgentKit stack locally, deploy it to Civo Cloud, and validate the workflow end to end.

---

## 1. Architecture Recap

- **Flask API (Python)** – Exposes `/api/agent` (POST) to enqueue prompts, persists state in SQLite, and `/api/agent/<request_id>` (GET) for polling status. Emits `app/agent.request` events via the Inngest Python SDK.
- **Agent Worker (Node.js)** – Runs an autonomous research agent with tool-calling capabilities backed by Ollama. The agent can search the web, look up current times in major cities, and retrieve dates when needed. It uses multi-step reasoning: first deciding if tools are needed, then executing them, and finally synthesizing results. Listens for Inngest events, executes the workflow, and posts results back to Flask at `/internal/agent-result`. *Note: We use Inngest's event-driven architecture (AgentKit pattern) without the literal `@inngest/agent-kit` package due to Python compatibility limitations.*
- **Start Script** – `start.sh` launches both Gunicorn (port 5000 by default) and the AgentKit service (port 3000) inside the same container.
- **Terraform** – Provisions a Civo compute instance with Docker, Ollama, Inngest Dev Server, and systemd services to run the application stack.

---

## 2. Prerequisites

| Tool | Recommended Version |
|------|---------------------|
| Python | 3.11 |
| Node.js | 20.x |
| Docker | Latest CE |
| Terraform | >= 1.6 |
| Inngest CLI | `npx inngest-cli@latest` |

You will also need:

- Civo API key (sign up at https://dashboard.civo.com/signup).
- For production: Inngest event/signing keys (from the Inngest dashboard).
- For development: Inngest Dev Server runs automatically (no keys needed).

---

## 3. Environment Configuration

Create a `.env` (or export variables in your shell) with values such as:

```bash
# For local development with Inngest Dev Server
export INNGEST_APP_ID="local-agent"
export INNGEST_DEV=1
export AGENT_RESULT_TOKEN="local-secret"
export OLLAMA_BASE_URL="http://localhost:11434/v1"
export FLASK_RUN_PORT=5000

# For production deployment (optional)
export INNGEST_SIGNING_KEY="<your-inngest-signing-key>"
export INNGEST_EVENT_KEY="<your-inngest-event-key>"
```

When deploying to Civo, these are configured via Terraform variables (see Section 6).

---

## 4. Local Development & Testing

1. **Install dependencies**
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   pip install -r app/requirements.txt

   npm install --prefix agent_service
   chmod +x start.sh
   ```

2. **Run supporting services**
   - Install and run Ollama locally: `curl -fsSL https://ollama.com/install.sh | sh && ollama serve`
   - Pull a model: `ollama pull llama3.2:3b`
   - Start the Inngest Dev Server:
     ```bash
     INNGEST_DEV=1 npx inngest-cli@latest dev -u http://localhost:3000/api/inngest
     ```

3. **Run the stack locally**
   ```bash
   export INNGEST_APP_ID="local-agent"
   export INNGEST_DEV=1
   export AGENT_RESULT_TOKEN="local-secret"
   export OLLAMA_BASE_URL="http://localhost:11434/v1"
   export FLASK_RUN_PORT=5000
   
   ./start.sh
   ```
   - Flask app will bind to `http://0.0.0.0:5000`.
   - Agent service listens at `http://0.0.0.0:3000/api/inngest`.

4. **Exercise the API**
   ```bash
   # Enqueue a request
   curl -X POST http://localhost:5000/api/agent \
     -H 'Content-Type: application/json' \
     -d '{"prompt":"Give me three insights about the EU AI Act."}'

   # Sample response: {"request_id":"<uuid>","status":"queued"}

   # Poll for completion (wait 2-3 seconds for Ollama to process)
   curl http://localhost:5000/api/agent/<uuid>
   ```

5. **Validate logs**
   - Flask logs: confirm enqueue + `/internal/agent-result` updates.
   - Inngest Dev Server UI (default `http://localhost:8288`): confirm function runs and completes.
   - Agent logs: look for tool calls like `TOOL_CALL: search_web(...)` or `TOOL_CALL: get_time_in_city(...)`.

**Agent Capabilities:**
The agent has access to three tools:
- `search_web(query)` - Searches DuckDuckGo for current information
- `get_time_in_city(city)` - Gets real-time data for major cities (Nairobi, London, New York, Tokyo, Paris, Sydney, Dubai, Los Angeles)
- `get_current_date()` - Returns today's date

Example prompts that trigger tool usage:
- "What are the latest developments in quantum computing?" → uses `search_web`
- "What time is it in Tokyo?" → uses `get_time_in_city`
- "Is there a GitHub user named okothmax?" → uses `search_web`

---

## 5. Build & Push the Container Image

```bash
docker build -t <registry>/<repo>:<tag> -f app/Dockerfile .
docker push <registry>/<repo>:<tag>
```

After the push, update `infra/helm/app/values.yaml`:

```yaml
image:
  repository: <registry>/<repo>
  tag: "<tag>"
```

---

## 6. Deployment Options

This project supports two deployment methods:

### 6.1 Compute Instance Deployment (Recommended for Development)

Deploy to a single Civo compute instance with Docker, Ollama, Inngest Dev Server, and the Flask application. This is the fastest way to get started and ideal for development/testing.

1. **Navigate to the Terraform directory:**
   ```bash
   cd terraform
   ```

2. **Create your configuration file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. **Edit `terraform.tfvars` with your settings:**
   ```hcl
   civo_token         = "your-civo-api-token"
   stack_name         = "llm-agent-compute"
   region             = "LON1"
   instance_size      = "g4s.large"
   inngest_app_id     = "civo-agent"
   agent_result_token = "your-secure-token"
   ```

4. **Deploy:**
   ```bash
   terraform init
   terraform apply
   ```

5. **Access your application:**
   
   After deployment (5-10 minutes), you'll see:
   ```
   app_public_ip  = "74.220.18.66"
   frontend_url   = "http://74.220.18.66:5000"
   inngest_dev_ui = "http://74.220.18.66:8288"
   ssh_command    = "ssh civo@74.220.18.66"
   ```

6. **Test the deployment:**
   ```bash
   # Test the API
   curl -X POST http://<your-ip>:5000/api/agent \
     -H 'Content-Type: application/json' \
     -d '{"prompt":"What time is it in Tokyo?"}'
   
   # Check status
   curl http://<your-ip>:5000/api/agent/<request_id>
   ```

**What Gets Deployed:**
- Civo compute instance (g4s.large: 4 CPU, 8GB RAM)
- Docker, Node.js 20.x, Ollama with llama3.2 model
- Systemd services for Ollama, Inngest Dev Server, and the app
- Firewall rules for ports 22, 80, 443, 3000, 5000, 8288, 11434

**Monitoring:**
```bash
ssh civo@<your-ip>

# Check services
sudo systemctl status ollama inngest-dev agent-app

# View logs
sudo journalctl -u agent-app -f
sudo journalctl -u inngest-dev -f

# Check startup script
sudo tail -f /var/log/startup.log
```

**Troubleshooting:**
If the Ollama model wasn't pulled correctly:
```bash
sudo HOME=/root ollama pull llama3.2:latest
sudo systemctl restart agent-app
```

For detailed documentation, see:
- `terraform/README.md` - Complete deployment guide
- `terraform/DEPLOY.md` - Quick reference

### 6.2 Alternative: Kubernetes Deployment (GPU Cluster)

For GPU-accelerated workloads, you can deploy to a Civo Kubernetes cluster. See the main `README.md` and `infra/tf/` directory for Kubernetes deployment instructions.

---

## 7. Post-Deployment Validation

### For Compute Instance Deployment:

1. Get your instance IP from Terraform output:
   ```bash
   cd terraform
   terraform output
   ```

2. Test the API:
   ```bash
   # Enqueue a request
   curl -X POST http://<instance-ip>:5000/api/agent \
     -H 'Content-Type: application/json' \
     -d '{"prompt":"What are the latest developments in quantum computing?"}'

   # Poll for result (replace <uuid> with the request_id from above)
   curl http://<instance-ip>:5000/api/agent/<uuid>
   ```

3. Access the Inngest Dev UI:
   ```
   http://<instance-ip>:8288
   ```

4. Monitor logs via SSH:
   ```bash
   ssh civo@<instance-ip>
   sudo journalctl -u agent-app -f
   sudo journalctl -u inngest-dev -f
   ```


---

## 8. Demo Checklist

1. Walk through repo structure (Flask API, Agent service with tools, Terraform deployment).
2. Explain the agent's tool-calling capabilities (web search, time lookup, date).
3. Show local run demonstrating:
   - Simple query (no tools needed)
   - Query requiring web search (e.g., "latest AI news")
   - Query requiring time lookup (e.g., "time in Nairobi")
4. Highlight multi-step reasoning in logs (decide → call tool → synthesize).
5. Show Inngest Dev Server traces with tool execution steps.
6. Demonstrate deployment on Civo compute instance and share the final IP.
7. Show the frontend UI and Inngest Dev UI at ports 5000 and 8288.
8. Close with agent architecture benefits (async, autonomous, tool-enabled).

---

## 9. Troubleshooting

| Symptom | Action |
|---------|--------|
| `401` on `/internal/agent-result` | Ensure `AGENT_RESULT_TOKEN` matches between Flask and AgentKit environments. |
| Inngest Dev Server cannot handshake | Confirm `INNGEST_SIGNING_KEY` is set; enable `INNGEST_DEV=1` for local/dev runs. |
| No response from Ollama | Validate the model is present: `sudo HOME=/root ollama list` on the instance. Pull if needed: `sudo HOME=/root ollama pull llama3.2:latest` |
| Model not found error | The app looks for `llama3.2:latest`. Pull it with: `sudo HOME=/root ollama pull llama3.2:latest` |
| Services not starting on instance | Check startup logs: `sudo tail -f /var/log/startup.log` and restart services: `sudo systemctl restart ollama inngest-dev agent-app` |
| Gunicorn fails to bind port locally | Override the port: `FLASK_RUN_PORT=5000 ./start.sh` |

---

