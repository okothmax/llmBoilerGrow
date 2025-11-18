import express from "express";
import { Inngest } from "inngest";
import { serve } from "inngest/express";
import OpenAI from "openai";
import "isomorphic-fetch";

const appId = process.env.INNGEST_APP_ID ?? "agentkit_service";
const eventKey = process.env.INNGEST_EVENT_KEY;
const signingKey = process.env.INNGEST_SIGNING_KEY;
const ollamaBaseUrl =
  process.env.OLLAMA_BASE_URL ?? "http://ollama.ollama.svc.cluster.local:11434/v1";
const flaskPort = process.env.FLASK_RUN_PORT ?? "5000";
const resultWebhookUrl =
  process.env.AGENT_RESULT_WEBHOOK ?? `http://127.0.0.1:${flaskPort}/internal/agent-result`;
const resultToken = process.env.AGENT_RESULT_TOKEN ?? "dev-token";
const port = Number(process.env.AGENTKIT_PORT ?? 3000);

const inngestClient = new Inngest({
  id: appId,
  eventKey,
  signingKey,
});

const ollamaClient = new OpenAI({
  baseURL: ollamaBaseUrl,
  apiKey: process.env.OLLAMA_API_KEY ?? "forced_key",
});

const app = express();
app.use(express.json());

// Agent Tools
const tools = {
  search_web: async (query) => {
    try {
      const response = await fetch(
        `https://api.duckduckgo.com/?q=${encodeURIComponent(query)}&format=json&no_html=1`
      );
      const data = await response.json();
      
      // Extract relevant results
      const results = [];
      if (data.AbstractText) {
        results.push({ source: "Abstract", text: data.AbstractText });
      }
      if (data.RelatedTopics && data.RelatedTopics.length > 0) {
        data.RelatedTopics.slice(0, 3).forEach((topic) => {
          if (topic.Text) {
            results.push({ source: "Related", text: topic.Text });
          }
        });
      }
      
      return results.length > 0
        ? JSON.stringify(results, null, 2)
        : "No relevant results found.";
    } catch (error) {
      return `Search failed: ${error.message}`;
    }
  },
  
  get_current_date: () => {
    return new Date().toISOString().split('T')[0];
  },
  
  get_time_in_city: async (city) => {
    try {
      // Use WorldTimeAPI for accurate timezone data
      const cityLower = city.toLowerCase();
      const timezoneMap = {
        'nairobi': 'Africa/Nairobi',
        'london': 'Europe/London',
        'new york': 'America/New_York',
        'tokyo': 'Asia/Tokyo',
        'paris': 'Europe/Paris',
        'sydney': 'Australia/Sydney',
        'dubai': 'Asia/Dubai',
        'los angeles': 'America/Los_Angeles',
      };
      
      const timezone = timezoneMap[cityLower] || 'UTC';
      const response = await fetch(`https://worldtimeapi.org/api/timezone/${timezone}`);
      
      if (!response.ok) {
        return `Could not fetch time for ${city}. Try: ${Object.keys(timezoneMap).join(', ')}`;
      }
      
      const data = await response.json();
      const datetime = new Date(data.datetime);
      return `Current time in ${city}: ${datetime.toLocaleString('en-US', { 
        timeZone: timezone,
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        timeZoneName: 'short'
      })}`;
    } catch (error) {
      return `Failed to get time: ${error.message}`;
    }
  }
};

const TOOL_DESCRIPTIONS = `Available tools:
1. search_web(query) - Search the web for current information
2. get_current_date() - Get today's date in YYYY-MM-DD format
3. get_time_in_city(city) - Get current time in a specific city (supports: Nairobi, London, New York, Tokyo, Paris, Sydney, Dubai, Los Angeles)

To use a tool, respond with: TOOL_CALL: tool_name(arguments)
Example: TOOL_CALL: search_web("latest AI regulations")
Example: TOOL_CALL: get_time_in_city("Nairobi")`;

async function postResult({ requestId, status, result }) {
  const response = await fetch(resultWebhookUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${resultToken}`,
    },
    body: JSON.stringify({ request_id: requestId, status, result }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Failed to post result: ${response.status} ${body}`);
  }
}

const agentWorkflow = inngestClient.createFunction(
  { id: "agentkit-process-request" },
  { event: "app/agent.request" },
  async ({ event, step, logger }) => {
    const {
      request_id: requestId,
      prompt,
      context,
      ollama_base_url: overrideBase,
    } = event.data;

    const baseUrl = overrideBase ?? ollamaBaseUrl;

    try {
      // Multi-step agent workflow with tool calling
      let finalResponse = await step.run("agent-reasoning", async () => {
        const systemPrompt = `You are an AI research analyst with access to tools. ${TOOL_DESCRIPTIONS}

If you need current information or data, use the appropriate tool. Otherwise, answer directly based on your knowledge.`;
        
        const userMessage = context
          ? `${context}\n\nUser request: ${prompt}`
          : prompt;
        const fullPrompt = `${systemPrompt}\n\n${userMessage}`;

        // First LLM call: decide if tools are needed
        const initialResponse = await fetch(`${baseUrl.replace('/v1', '')}/v1/completions`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            model: process.env.OLLAMA_MODEL ?? "llama3.2:latest",
            prompt: fullPrompt,
            temperature: 0.2,
            max_tokens: 800,
          }),
        });

        if (!initialResponse.ok) {
          throw new Error(`Ollama returned ${initialResponse.status}: ${await initialResponse.text()}`);
        }

        const initialData = await initialResponse.json();
        const agentResponse = initialData.choices[0]?.text ?? "No response produced.";
        
        // Check if agent wants to use a tool
        const toolCallMatch = agentResponse.match(/TOOL_CALL:\s*(\w+)\(([^)]*)\)/);
        
        if (toolCallMatch) {
          const [, toolName, toolArgs] = toolCallMatch;
          
          if (tools[toolName]) {
            // Execute the tool
            const toolResult = await tools[toolName](toolArgs.replace(/["']/g, ''));
            
            // Second LLM call: synthesize with tool results
            const synthesisPrompt = `${systemPrompt}\n\nUser request: ${prompt}\n\nTool used: ${toolName}\nTool result:\n${toolResult}\n\nProvide a comprehensive answer using this information:`;
            
            const finalResponse = await fetch(`${baseUrl.replace('/v1', '')}/v1/completions`, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({
                model: process.env.OLLAMA_MODEL ?? "llama3.2:latest",
                prompt: synthesisPrompt,
                temperature: 0.2,
                max_tokens: 1000,
              }),
            });
            
            if (!finalResponse.ok) {
              throw new Error(`Ollama synthesis failed: ${finalResponse.status}`);
            }
            
            const finalData = await finalResponse.json();
            return finalData.choices[0]?.text ?? agentResponse;
          }
        }
        
        // No tool call needed, return initial response
        return agentResponse;
      });

      await postResult({ requestId, status: "completed", result: finalResponse });

      return { requestId, status: "completed" };
    } catch (error) {
      logger?.error?.("AgentKit workflow failed", { error });
      const message =
        error instanceof Error ? error.message : "Unknown agent failure";
      await postResult({ requestId, status: "failed", result: message });
      throw error;
    }
  }
);

app.get("/healthz", (_req, res) => {
  res.json({ status: "ok" });
});

app.use(
  "/api/inngest",
  serve({
    client: inngestClient,
    functions: [agentWorkflow],
  })
);

const server = app.listen(port, () => {
  console.log(`AgentKit service listening on port ${port}`);
});

export default server;
