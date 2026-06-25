# Runbook: Onboard a Tool (REST API → MCP Server)

> **PREVIEW.** No stable Bicep type — provisioned via `scripts/provision-preview.*` and
> portal/CLI guidance.

Expose an existing REST API in APIM as an MCP server so agents can call its operations as
governed tools. This is the **agent → tool** surface — see
[mcp-tools](../controls/mcp-tools.md).

## Steps

1. **Import the REST API** into APIM (if not already present).

2. **Expose it as an MCP server.** Run:

   ```bash
   scripts/provision-preview.sh    # or .ps1
   ```

   Or, in the portal: select the API → expose as MCP server. Each API operation becomes
   an MCP tool. The endpoint is:

   ```
   https://<apim>.azure-api.net/<api>-mcp/mcp
   ```

   Transport: streamable HTTP at `/mcp`.

3. **Attach governance.** Apply `infra/policies/mcp-governance.xml`
   (`rate-limit-by-key` + agent-id trace, optional `validate-jwt`).

## Whole-server scope caveat

Governance applies to the **WHOLE MCP server, not per tool**. One policy covers every
operation on the server — you cannot independently rate-limit or gate a single tool. If
you need different limits per tool, split into separate MCP servers.

Also: **do not access `context.Response.Body`** in MCP policies — it breaks streaming.

## Test from VS Code

1. Open VS Code with an MCP-capable client.
2. Add the server URL `https://<apim>.azure-api.net/<api>-mcp/mcp`.
3. Supply a team subscription key.
4. Confirm the API operations appear as callable tools and that calls are rate-limited
   per the policy.
