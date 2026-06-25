# ADR-0004 — Unified doorway pattern, Azure OpenAI as the sole live backend

**Status:** Accepted · **Date:** 2026-06-25

## Context
Two of the chosen options are in mild tension: **model scope = Azure OpenAI only** (every control GA-stable) but **maturity stance = full showcase including the unified "one doorway"**. The doorway exists precisely to abstract *multiple* providers, so a single-provider doorway is, on its face, degenerate.

## Decision
Build the **unified model API doorway pattern**, but point it at **Azure OpenAI as the only live backend**. Document adding Claude/Gemini as a backend-pool + tier change, not a rearchitecture.

## Rationale
- It demonstrates the article's punchline — one client-facing endpoint (`/llm/v1/chat/completions`), one set of governance policies, provider abstraction behind the door — without taking on the instability of running multiple preview-translated providers in the golden copy.
- Governed traffic stays single-provider and GA-stable (no Anthropic-translation preview in the hot path), satisfying the "OpenAI only" choice.
- The pattern is the point: the doorway stays put; you point it somewhere new. Adding Claude = add a backend (API format Anthropic Messages) + StandardV2 tier. See [runbooks/add-claude.md](../runbooks/add-claude.md).

## Consequences
- The unified API is provisioned as a preview surface (per [ADR-0003](0003-preview-via-scripts.md)) alongside the primary `/openai` LLM API, which remains the day-one governed path.
- If the org later standardises on multi-provider, the doorway is already in place — only backends and tier change.
