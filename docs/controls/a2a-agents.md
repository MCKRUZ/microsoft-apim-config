# A2A Agents (agent → agent surface)

> **PREVIEW.** Management APIs are unstable and lack stable Bicep types. Provisioned via
> portal/CLI guidance in `scripts/provision-preview.*`, not declarative IaC.

See [architecture](../architecture.md) and [caveats](../caveats.md).

## What it governs

The **agent → agent (A2A)** traffic surface. APIM imports an A2A (Agent2Agent) JSON-RPC
agent and mediates the JSON-RPC traffic between caller and callee agent. The gateway
invariant holds: agent-to-agent calls are governed, traced, and identity-bound like every
other surface.

## Endpoint / shape

JSON-RPC. On import APIM **re-projects the agent card**:

- rewrites the hostname to the APIM host,
- sets the JSON-RPC transport,
- adds a subscription-key requirement.

It emits OpenTelemetry `gen_ai.agent.id` and `gen_ai.agent.name` spans for tracing.

## How to provision

1. Run `scripts/provision-preview.{sh,ps1}` — handles the A2A import (no stable Bicep type
   yet).
2. Or in the portal: import the A2A agent by its JSON-RPC endpoint; APIM generates the
   re-projected agent card.
3. Attach the governance policy below.

## Governance policy

`infra/policies/a2a-governance.xml`.

## Limitations / caveats

- **JSON-RPC only.**
- **No outgoing response-body deserialization** — policies cannot inspect/transform the
  JSON-RPC response payload.
- Preview: import behavior and card projection may change.

## Test

Call the re-projected agent card URL on the APIM host with a team subscription key;
confirm the hostname is rewritten to APIM and that `gen_ai.agent.id` /
`gen_ai.agent.name` appear in the OTel trace.
