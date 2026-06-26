# ADR-0003 — Preview surfaces provisioned via scripts, not Bicep

**Status:** Accepted · **Date:** 2026-06-25

## Context
The showcase includes features that are not yet final ("preview"): the tool server (MCP), the agent-to-agent (A2A) API, and the one-endpoint model API that can front multiple model vendors. The production-ready ("GA", generally available) core is defined cleanly in Azure's deployment templates (Bicep/ARM). But these preview features are brand new (2025–2026) and the way you set them up is still changing.

## Decision
Build the **GA core entirely as Bicep templates** (`infra/`). Set up the **preview features through scripts that run after deployment** (`scripts/provision-preview.*`). Those scripts use Azure's command-line tools where they're stable, and otherwise print the exact portal click-path plus links to the official docs. The script is wired to run automatically right after deploy (via `azd`'s `postprovision` hook).

## Rationale
- Confirmed: the tool server (MCP), the A2A agent API, and the one-endpoint model API are documented only as portal/command-line/REST steps, with the matching Bicep/ARM building blocks either missing or not yet stable. Pretending they were Bicep would be dishonest and would break the next time the API changes.
- A guided script that points to the exact portal steps and the governance rules file to paste in is more durable than fragile automated calls against features that are still shifting.
- It keeps a clean dividing line: anything in `infra/` is production-ready and repeatable; anything in `scripts/provision-preview.*` is preview and may need updating.

## Also covered here
The content-safety service signs in using **an Azure-issued identity the service owns (a managed identity, so no stored password)**. This is a production-ready control, but it hits the same wall — the Bicep/ARM templates don't yet support setting it (confirmed through API version `2025-09-01-preview`). So it's handled by `scripts/configure-backend-auth.*` (run as part of `provision-preview`), with a single portal toggle as a fallback. See [caveats.md](../caveats.md) §3.

## Consequences
- `azd up` provisions GA infra, then the postprovision hook configures content-safety MI and prints preview-provisioning guidance.
- When Microsoft ships stable Bicep types for these surfaces, migrate them from `scripts/` into `infra/` and update this ADR.
