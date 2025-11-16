# Civo LLM Boilerplate – Run Book

This document explains how to configure the asynchronous Flask + AgentKit stack locally, deploy it to the Civo GPU cluster, and validate the workflow end to end.

---

## 1. Architecture Recap

- **Flask API (Python)** – Exposes `/api/agent` (POST) to enqueue prompts, persists state in SQLite, and `/api/agent/<request_id>` (GET) for polling status. Emits `app/agent.request` events via the Inngest Python SDK.
- **Agent Worker (Node.js)** – Runs an autonomous research agent with tool-calling capabilities backed by Ollama. The agent can search the web, look up current times in major cities, and retrieve dates when needed. It uses multi-step reasoning: first deciding if tools are needed, then executing them, and finally synthesizing results. Listens for Inngest events, executes the workflow, and posts results back to Flask at `/internal/agent-result`. *Note: We use Inngest's event-driven architecture (AgentKit pattern) without the literal `@inngest/agent-kit` package due to Python compatibility limitations.*
- **Start Script** – `start.sh` launches both Gunicorn (port 80) and the AgentKit service (port 3000) inside the same container.
- **Terraform + Helm** – Terraform provisions the Civo cluster and installs Helm charts (Ollama, Web UI, example app). The Helm chart deploys the combined container and wires environment variables.

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

- Civo API key with GPU quota.
- Inngest event/signing keys (from the Inngest dashboard).
- Access to an Ollama instance (deployed via Terraform in this repo).

---

## 3. Environment Configuration

Create a `.env` (or export variables in your shell) with values such as:

```bash
export INNGEST_APP_ID="civo-llm-agent"
export INNGEST_SIGNING_KEY="<your-inngest-signing-key>"
# Optional: only required when sending events from Node
export INNGEST_EVENT_KEY="<your-inngest-event-key>"

export AGENT_RESULT_TOKEN="replace-with-random-string"
export OLLAMA_BASE_URL="http://localhost:11434/v1"  # when port-forwarding Ollama locally
```

When deploying to Kubernetes, set the same keys through Helm values (see Section 6.2). Keep sensitive values in Kubernetes secrets.

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
   - Port-forward Ollama if running in-cluster: `kubectl port-forward svc/ollama 11434:11434 -n ollama`.
   - Start the Inngest Dev Server (requires `INNGEST_DEV=1` in both services):
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
   - Gunicorn will bind to `http://0.0.0.0:5000` locally (or port 80 in container).
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

## 6. Kubernetes Deployment

### 6.1 Terraform

1. Populate `infra/tf/terraform.tfvars` with your Civo token:
   ```hcl
   civo_token = "YOUR_CIVO_TOKEN"
   ```
2. Enable application deployment (either update `infra/tf/variables.tf` or override via tfvars):
   ```hcl
   deploy_app = true
   ```
3. Execute Terraform:
   ```bash
   cd infra/tf
   terraform init
   terraform plan -out=plan.out
   terraform apply plan.out
   ```

Terraform outputs include the app LoadBalancer IP (`ollama_app_load_balancer_ip`).

### 6.2 Helm values & secrets

Set environment variables for the pod in `infra/helm/app/values.yaml`:

```yaml
env:
  - name: INNGEST_APP_ID
    value: "civo-llm-agent"
  - name: OLLAMA_BASE_URL
    value: "http://ollama.ollama.svc.cluster.local:11434/v1"
  - name: AGENT_RESULT_TOKEN
    valueFrom:
      secretKeyRef:
        name: app-secrets
        key: agent_result_token

secretEnv:
  - name: INNGEST_SIGNING_KEY
    secretName: app-secrets
    secretKey: inngest_signing_key
  - name: INNGEST_EVENT_KEY
    secretName: app-secrets
    secretKey: inngest_event_key
```

Create the secret (example):

```bash
kubectl create secret generic app-secrets \
  --namespace apps \
  --from-literal=agent_result_token=<random> \
  --from-literal=inngest_signing_key=<signing-key> \
  --from-literal=inngest_event_key=<event-key>
```

Re-run `terraform apply` if values change.

---

## 7. Post-Deployment Validation

1. Retrieve the application IP from Terraform output or via `kubectl get svc -n apps`. Example placeholder:
   
   > **Live IP:** `TODO_REPLACE_WITH_CLUSTER_IP`

2. Test from your machine:
   ```bash
   curl -X POST http://<live-ip>/api/agent \
     -H 'Content-Type: application/json' \
     -d '{"prompt":"Summarise the benefits of owning data sovereignty."}'

   curl http://<live-ip>/api/agent/<uuid>
   ```

3. Monitor logs:
   ```bash
   kubectl logs deploy/app -n apps -c app --follow
   kubectl logs deploy/app -n apps -c agentkit --follow  # if split containers are used later
   ```

---

## 8. Loom Demo Checklist

1. Walk through repo structure (Flask API, Agent service with tools, Terraform/Helm).
2. Explain the agent's tool-calling capabilities (web search, time lookup, date).
3. Show local run demonstrating:
   - Simple query (no tools needed)
   - Query requiring web search (e.g., "latest AI news")
   - Query requiring time lookup (e.g., "time in Nairobi")
4. Highlight multi-step reasoning in logs (decide → call tool → synthesize).
5. Show Inngest Dev Server traces with tool execution steps.
6. Demonstrate deployment on Civo and share the final IP.
7. Close with agent architecture benefits (async, autonomous, tool-enabled).

---

## 9. Troubleshooting

| Symptom | Action |
|---------|--------|
| `401` on `/internal/agent-result` | Ensure `AGENT_RESULT_TOKEN` matches between Flask and AgentKit environments. |
| Inngest Dev Server cannot handshake | Confirm `INNGEST_SIGNING_KEY` is set and reachable from the pod; enable `INNGEST_DEV=1` for local runs. |
| No response from Ollama | Validate the model is present (`terraform apply` pulls defaults) and that the service name is correct. |
| Gunicorn fails to bind port 80 locally | Run with elevated privileges or override the port (`FLASK_RUN_PORT=5000 ./start.sh`). |

---

## 10. Deliverables Checklist

- [ ] GitHub repository with updated implementation.
- [ ] Loom video (5–10 minutes) covering approach and demo.
- [ ] Live IP address from the deployed Civo cluster: `TODO_REPLACE_WITH_CLUSTER_IP`.

---

Happy shipping!
