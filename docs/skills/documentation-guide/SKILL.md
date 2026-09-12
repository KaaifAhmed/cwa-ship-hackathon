---
name: documentation-guide
description: >-
  Governs project documentation creation, README structure, and accuracy audits for Phase 8 of development.
  Use this skill when writing or updating README.md, reviewing architectural or SRS documentation for drift,
  eliminating duplicate documentation, or auditing docs against hackathon submission criteria.
---

# Documentation Guide — CWA Ship Karachi 2026

**Purpose:** Govern documentation creation and accuracy checks during Phase 8 (25 minutes). Every sentence must justify its inclusion. Unread or outdated documentation introduces overhead and confusion.

---

## 1. Core Idea: Finalize Existing Docs, Rarely Create New Ones

Most documentation is authored during earlier phases. Phase 8 performs a rapid verification pass:

| Document | Authoring Stage | Phase 8 Action |
|---|---|---|
| `architecture.md` | Pre-hackathon / Phase 2 | Check against built code: fix endpoint drift or model divergence. Do not rewrite. |
| `srs.md` | Phase 1 | Confirm alignment with final delivered scope. Minor edits only. |
| `sdlc.md`, `skills/` | Pre-hackathon | Process documents — keep stable. |
| **`README.md`** | **Phase 8** | **The single new document authored at wrap-up.** |

---

## 2. README.md Specifications

The `README.md` serves as the primary entry point for evaluators and developers. An external engineer or judge must be able to run and understand the project using this file alone.

### Required README Structure
1. **What It Is:** Exactly one clear paragraph defining the problem, target user, and core solution without marketing hyperbole.
2. **How to Run It:** Bulletproof, copy-pasteable terminal commands (`docker compose up -d --build`, seed commands, migrations).
3. **How It Works:** Concise architectural overview linking to `architecture.md` and `srs.md` for in-depth details.
4. **Demo Flow:** Step-by-step numbered walkthrough matching the primary user journey from `ux-guidelines`, enabling judges to verify the system live.
5. **Out of Scope / Limitations:** Explicit list of deliberate constraints (demonstrates intentional design rather than omissions).

---

## 3. Documentation Rules

- **Plain, Direct Language:** Active voice, short sentences, technical clarity.
- **Single Source of Truth (Say It Once):** Never duplicate facts across files. Link to the canonical reference.
- **Zero Fluff:** If a section contains no functional value, delete it.
- **Target a 3-Minute Read:** The entire README must be fully digestible in under three minutes.
- **Demonstrate with Exact Commands:** Show concrete shell snippets and endpoints rather than abstract descriptions.

---

## 4. Prohibited Documentation Artifacts

Do not spend time producing:
- Standalone user manuals (covered in the README demo flow).
- Hand-crafted API references (link directly to auto-generated Swagger UI / OpenAPI docs).
- Detailed changelogs or contribution guides for hackathon deliverables.
- Redundant summaries that duplicate existing architecture files.

---

## 5. Definition of Done (Documentation Review)

Documentation is submission-ready when:
- [ ] `README.md` exists and allows a newcomer to spin up the entire application using copy-paste commands.
- [ ] `architecture.md` and `srs.md` accurately reflect delivered software, not stale plans.
- [ ] No duplicated facts exist across documents — all details link back to primary sources.
- [ ] Redundant or speculative prose has been pruned.
- [ ] Entire README can be thoroughly reviewed within 3 minutes.
