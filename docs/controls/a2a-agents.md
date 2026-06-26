# A2A Agents (agent → agent surface)

> **PREVIEW.** Management APIs are unstable and lack stable Bicep types. Provisioned via
> portal/CLI guidance in `scripts/provision-preview.*`, not declarative IaC.

See [architecture](../architecture.md) and [caveats](../caveats.md).

## What it governs

This covers traffic where **one agent calls another agent** — "agent-to-agent," or A2A. The
API gateway (Azure API Management, "APIM") registers an A2A agent (A2A stands for
Agent2Agent) and sits in the middle of the conversation between the calling agent and the
one being called. Those calls use JSON-RPC, a standard request format. The core rule of the
gateway still holds: agent-to-agent calls are governed, traced, and tied to a verified
identity like every other kind of traffic.

## Endpoint / shape

Calls use JSON-RPC (a standard request format). When an agent is registered, the gateway
rewrites that agent's published description (its "agent card") so callers go through the
gateway instead of straight to the agent. Specifically it:

- changes the address to the gateway's address,
- sets the JSON-RPC transport,
- requires a subscription key (a per-team access key).

For tracing it emits `gen_ai.agent.id` and `gen_ai.agent.name` records in the
OpenTelemetry format (OTel, a telemetry standard).

## How to provision

1. Run `scripts/provision-preview.{sh,ps1}` — handles the A2A import (no stable Bicep type
   yet).
2. Or in the portal: import the A2A agent by its JSON-RPC endpoint; the gateway generates
   the rewritten agent card.
3. Attach the governance policy below.

## Governance policy

`infra/policies/a2a-governance.xml`.

## Limitations / caveats

- **JSON-RPC only.**
- **No outgoing response-body deserialization** — policies cannot inspect/transform the
  JSON-RPC response payload.
- Preview: import behavior and card projection may change.

## Test

Call the rewritten agent-card URL on the gateway host with a team subscription key; confirm
the address now points to the gateway and that `gen_ai.agent.id` / `gen_ai.agent.name`
appear in the OpenTelemetry (OTel) trace.
