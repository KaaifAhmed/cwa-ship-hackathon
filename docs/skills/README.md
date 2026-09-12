# Antigravity Skills

This directory contains workspace skills discovered and loaded by Google Antigravity.
Configured via [`.agents/skills.json`](../../.agents/skills.json).

## Available Skills

| Skill | Path | Description |
|---|---|---|
| **`coding-guidelines`** | [`coding-guidelines/SKILL.md`](./coding-guidelines/SKILL.md) | Enforces PEP 8, Django/DRF, and React standards, encapsulation, and definition of done. |
| **`testing-guidelines`** | [`testing-guidelines/SKILL.md`](./testing-guidelines/SKILL.md) | Lightweight TDD, contract testing, unit/component/system levels, and mock rules. |
| **`ui-guidelines`** | [`ui-guidelines/SKILL.md`](./ui-guidelines/SKILL.md) | Material Design 3 structure, 4px spacing, role-based colors, and Tailwind configuration. |
| **`ux-guidelines`** | [`ux-guidelines/SKILL.md`](./ux-guidelines/SKILL.md) | Journey mapping workflow, progressive disclosure, state feedback, and single primary action. |
| **`documentation-guide`** | [`documentation-guide/SKILL.md`](./documentation-guide/SKILL.md) | Phase 8 documentation protocol, README.md structure, and accuracy audit rules. |

## Antigravity Discovery

These skills are registered in `.agents/skills.json` at the root of the workspace:

```json
{
  "entries": [
    {
      "path": "docs/skills"
    }
  ]
}
```
Antigravity automatically discovers these skills using progressive disclosure, injecting descriptions into agent context and loading the full skill when activated.
