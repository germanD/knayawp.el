---
title: knayawp.el Knowledge Base
last-updated: 2026-08-10
status: draft
---

# knayawp.el — Knowledge Base

An opinionated Emacs package for project-oriented window layouts. Editor on the left,
tools (magit, terminal, Claude Code) stacked on the right — automatically.

## Taxonomy

| File / Directory | What goes here |
|---|---|
| `spec.md` | *What* the system does — features, UX, user-facing options |
| `properties.md` | *Must never happen* — invariants and correctness constraints |
| `decisions/` | *Why this approach* — one ADR per key design choice |
| `ideas.md` | *Might do someday* — incubator, not yet committed work |

**Rule of thumb:** if you're documenting a feature → `spec.md`. A constraint that code
must not violate → `properties.md`. The reason a non-obvious design was chosen →
`decisions/`. A rough future idea → `ideas.md`.

## KB Files

- [spec.md](spec.md) — Product specification: features, UX, user-facing customization
- [properties.md](properties.md) — Invariants: correctness constraints that must hold
  at all times; if code contradicts a property, the code is wrong
- [ideas.md](ideas.md) — Incubator: forward-looking ideas not yet scoped as issues

## Architecture Decision Records

Key design choices with their context and trade-offs:

- [ADR-001](decisions/adr-001-side-windows.md) — Use side windows for the control pane
- [ADR-002](decisions/adr-002-no-advice.md) — Zero advice on built-in functions
- [ADR-003](decisions/adr-003-terminal-isolation.md) — Terminal backend abstraction
- [ADR-004](decisions/adr-004-with-editor-cooperation.md) — with-editor winconf
  cooperation for commit zoom

## Related Project Files

- `PLAN.md` — Implementation roadmap with milestones and task checklists
- `AGENTS.md` — Agent instructions, coding conventions, and elisp best practices
- `CLAUDE.md` — Project rules for Claude Code

## Maintenance

The KB is the source of truth for *what the system is intended to be*. The code is the
source of truth for *what currently exists*. When they diverge:

- Code contradicts `properties.md` → the **code is wrong**; fix the code.
- Code has features not in `spec.md` → the **KB is missing**; update `spec.md`.
- `spec.md` describes something not implemented → it is **planned work**; leave it.

Periodic gap audits are handled by the `kb-librarian` agent. Run `/kb-audit` to
trigger a manual audit, or `/kb-audit --fix` to audit and apply fixes.
