# MCP Tools (agent → tool surface)

> **PREVIEW.** Management APIs are unstable and lack stable Bicep types. Provisioned via
> portal/CLI guidance in `scripts/provision-preview.*`, not declarative IaC.

See [architecture](../architecture.md) and [caveats](../caveats.md).

## What it governs

This covers the traffic where an **agent calls a tool** — that is, an agent reaching out to
an external function or service to get something done. The API gateway (Azure API
Management, "APIM") takes an existing web API (a REST API) and presents it as a *tool
server* (an "MCP server", MCP being the standard agents use to call tools): each operation
of that API becomes a tool the agent can call. The core rule of the gateway still holds —
an agent can only reach a tool by going through the gateway — so the same rate limits,
identity checks, and tracing that apply to model calls also apply to tool calls.

## Endpoint / shape

```
https://<apim>.azure-api.net/<api>-mcp/mcp
```

Transport: **streamable HTTP** at `/mcp`.

## How to provision

1. Run `scripts/provision-preview.{sh,ps1}` — it walks the preview steps (no stable Bicep
   type exists yet).
2. Or in the portal: select the REST API → expose as MCP server. Operations become tools.
3. Attach the governance policy (below) at the MCP server scope.

## Governance policy

`infra/policies/mcp-governance.xml` — `rate-limit-by-key` + an agent-id trace, with an
optional `validate-jwt`.

```xml
<inbound>
    <rate-limit-by-key calls="{{mcp-calls}}" renewal-period="60"
        counter-key="@(context.Subscription.Id)" />
    <trace source="mcp-governance">
        <message>@($"agent={context.Request.Headers.GetValueOrDefault('x-agent-id','unknown')}")</message>
    </trace>
    <!-- optional: <validate-jwt .../> -->
</inbound>
```

## Limitations / caveats

- **Governance scope is WHOLE-SERVER, not per-tool.** One policy covers every tool on the
  server; you cannot rate-limit or gate a single operation independently.
- **Do NOT access `context.Response.Body`** in MCP policies — it breaks streaming.
- Preview: endpoint shape and management surface may change.

## Test

From VS Code (MCP-capable client), point at
`https://<apim>.azure-api.net/<api>-mcp/mcp`, supply a team subscription key, and confirm
the API operations appear as callable tools. See
[runbooks/onboard-a-tool](../runbooks/onboard-a-tool.md).
