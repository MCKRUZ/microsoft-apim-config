# Request flow — a governed model call

How a single agent → model request is governed end-to-end, in policy order. This is the inbound pipeline from `infra/policies/llm-governance.xml`.

```mermaid
sequenceDiagram
    participant Agent
    participant APIM as APIM gateway
    participant CS as Content Safety
    participant Redis as Redis (RediSearch)
    participant AOAI as Azure OpenAI
    participant AI as App Insights

    Agent->>APIM: POST /openai/.../chat/completions (api-key = team identity)
    Note over APIM: authentication-managed-identity<br/>(AAD token for Azure OpenAI — keyless)
    APIM->>APIM: llm-token-limit (pre-flight estimate)
    alt over rate / quota
        APIM-->>Agent: 429 (rate) / 403 (quota) — never bills the model
    end
    APIM->>AI: llm-emit-token-metric (Subscription, Product, API, Agent ID)
    APIM->>CS: llm-content-safety (shield-prompt + harm categories)
    alt jailbreak / unsafe
        CS-->>APIM: attack detected
        APIM-->>Agent: 403 — blocked before the model
    end
    APIM->>Redis: llm-semantic-cache-lookup (vectorise via embeddings)
    alt semantic hit
        Redis-->>APIM: cached completion
        APIM-->>Agent: 200 (cached) — model not called, not billed
    else miss
        APIM->>AOAI: forward chat completion
        AOAI-->>APIM: completion (+ usage tokens)
        APIM->>Redis: llm-semantic-cache-store (TTL 3600s)
        APIM-->>Agent: 200
    end
```

## Why this order

1. **Managed identity first** — attach the keyless AAD token before anything routes to the model.
2. **Token limit before everything billable** — a rejected request piles up against the gate, not the invoice.
3. **Emit metrics** — every request is attributed to a team, hit or miss.
4. **Content safety before cache** — the *incoming* prompt is always screened, even when a cache hit will short-circuit the model. A cached answer was screened when stored; the new prompt still must be.
5. **Cache lookup last (inbound)** — so spend caps, attribution, and safety always evaluate; a hit then saves the backend call.

The trade-off in step 4/5 (screen-before-cache vs cache-before-screen to save the safety call on hits) is deliberate: this golden copy chooses **safety-first**. See [controls/semantic-cache.md](../controls/semantic-cache.md).
