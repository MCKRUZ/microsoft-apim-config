# ADR-0003 — Preview surfaces provisioned via scripts, not Bicep

**Status:** Accepted · **Date:** 2026-06-25

## Context
The user chose a full showcase including the preview surfaces (MCP server, A2A agent API, unified model API). The GA core is clean Bicep. But the preview constructs are new in 2025–2026 and their management APIs are still moving.

## Decision
Implement the **GA core as pure Bicep** (`infra/`). Provision the **preview surfaces via post-deploy scripts** (`scripts/provision-preview.*`) that attempt `az rest`/CLI where stable and otherwise print authoritative portal steps + doc links. Wire the script into `azd` as a `postprovision` hook.

## Rationale
- Verified: MCP server, A2A agent API, and unified model API are documented as **portal/CLI/REST** experiences with immature or absent stable ARM/Bicep resource types. Faking them as Bicep would be dishonest and would break on the next API revision.
- A guided script that points at the exact portal flow and the governance policy file to paste is more durable than brittle calls to shifting preview endpoints.
- Keeps a clean line: if it's in `infra/` it's GA and reproducible; if it's in `scripts/provision-preview.*` it's preview and may need updating.

## Also covered here
The content-safety **backend managed-identity auth** is a GA control that hits the same wall — it's not in the ARM backend schema (verified through `2025-09-01-preview`). It's handled by `scripts/configure-backend-auth.*` (chained from `provision-preview`), with a one-toggle portal fallback. See [caveats.md](../caveats.md) §3.

## Consequences
- `azd up` provisions GA infra, then the postprovision hook configures content-safety MI and prints preview-provisioning guidance.
- When Microsoft ships stable Bicep types for these surfaces, migrate them from `scripts/` into `infra/` and update this ADR.
