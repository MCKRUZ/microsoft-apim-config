# ADR-0004 — Unified doorway pattern, Azure OpenAI as the sole live backend

**Status:** Accepted · **Date:** 2026-06-25

## Context
Two earlier choices pull against each other. One: stick to **Azure OpenAI only**, because every control is production-ready and stable there. The other: show the full picture, **including the "unified doorway" — one endpoint that fronts multiple model vendors**. The whole reason a unified doorway exists is to hide *several* providers behind one entrance, so building one with a single provider behind it looks, at first glance, pointless.

## Decision
Build the **unified doorway pattern**, but wire it to **Azure OpenAI as the only live provider behind it**. Document that adding Anthropic's Claude or Google's Gemini later is just adding a backend and changing tier — not a redesign.

## Rationale
- It shows the main idea — one endpoint for callers (`/llm/v1/chat/completions`), one set of governance rules, and the choice of provider hidden behind it — without the instability of running several not-yet-final, format-translated providers in the reference build.
- The governed traffic stays single-provider and production-ready (no preview Anthropic translation in the live path), which honors the "OpenAI only" choice.
- The pattern is the point: the doorway stays where it is and you simply point it somewhere new. Adding Claude means adding a backend (using Anthropic's Messages API format) and moving to the StandardV2 tier. See [runbooks/add-claude.md](../runbooks/add-claude.md).

## Consequences
- The unified doorway is set up as a not-yet-final ("preview") feature (per [ADR-0003](0003-preview-via-scripts.md)), running alongside the primary `/openai` model API, which stays the governed path from day one.
- If the org later moves to multiple providers, the doorway is already in place — only the backends and the tier change.
