---
name: coding-guidelines
description: >-
  Enforces project-wide coding standards, architectural boundaries, and implementation conventions for Python/Django and React.
  Use this skill whenever writing, modifying, refactoring, or reviewing backend or frontend code, implementing API endpoints or data models,
  or evaluating code against the project Definition of Done.
---

# Coding Guidelines — CWA Ship Karachi 2026

**Purpose:** Production-grade code, written fast, by AI agents directed by human engineers. These rules exist to keep every component simple, readable, and safely swappable — avoiding unnecessary abstraction or process for its own sake.

---

## 1. Core Philosophy

1. **Simple and monolithic within a component:**
   - Do not split a component into unnecessary files or folders.
   - One clear `models.py`, one clear `views.py`, one clear `serializers.py` beats ten files of premature "organization".
   - Split only when a file is genuinely doing two unrelated jobs — never preemptively.
2. **Every line fights for its place:**
   - No speculative abstractions, no "might need this later" code, no unused imports, functions, or configurations.
   - If it is not required for the current contract, do not write it.
3. **Self-explanatory over clever:**
   - Any engineer should be able to read a function and understand what it does without comments.
   - Clear naming and straight-line logic beat clever one-liners.
4. **Follow the framework's own conventions:**
   - Django/DRF has an idiomatic pattern for almost everything (model validation, serializers, class-based views, migrations, settings via environment variables). Use them.
   - Do not invent custom patterns where Django/React standard patterns exist — custom patterns introduce extra code and unnecessary cognitive load.
5. **Build to the contract, not past it:**
   - Every component has a locked input/output contract established in design.
   - Implement exactly that contract. Nothing outside the contract is needed, and nothing inside the contract should be omitted.

---

## 2. Boundaries & Encapsulation

- **Internal Freedom vs. Contract Stability:** A component's internals (model fields beyond what the contract exposes, helper functions, internal logic) can change freely without external sign-off, **provided the contract's inputs and outputs stay identical**.
- **No Cross-Database Leaks:** Never let one component reach directly into another component's database or internal tables. All cross-component interactions must go through defined APIs or event buses.
- **Boundary Validation:** Validate everything at the boundary (e.g., DRF serializers, schema validators). Once data is inside the component, trust it — avoid redundant defensive validation everywhere.

---

## 3. Standard Response Envelope & Error Handling

All endpoints must return the standard response envelope defined in the system architecture:

```json
{
  "success": true,
  "data": { ... },
  "error": null
}
```

Or for failures:

```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "INVALID_CREDENTIALS",
    "message": "Invalid username or password."
  }
}
```

- **Handle realistic errors:** Focus on failure modes that actually occur in practice (bad input, resource not found, authentication/authorization failures) with correct HTTP status codes (`400`, `401`, `403`, `404`, `500`).
- **No blanket exception swallowing:** Avoid wrapping large code blocks in defensive `try/except Exception: pass` — that hides real bugs instead of preventing them.

---

## 4. Comments & Cleanliness

- **Comment *why*, not *what*:** If a comment merely restates the code below it, delete the comment.
- **Zero dead code:** No commented-out blocks of code.
- **Zero leftover TODOs:** Resolve items or remove the comment before submission.

---

## 5. Incremental, Modular Development Workflow

1. Break down component implementation into a small ordered list of modules (e.g., `user model` → `registration endpoint` → `login endpoint` → `token issuance`).
2. Implement one module fully — working, tested, and passing its test — before starting the next.
3. Never maintain multiple half-built modules simultaneously.

---

## 6. Language & Framework Standards

### Python & Django
- Adhere to **PEP 8** style guidelines.
- Follow standard Django application layout (`models.py`, `views.py`, `serializers.py`, `urls.py`).
- Secrets and configuration must strictly come from `.env` via environment variables (never hardcoded).
- Keep database migrations committed alongside the model changes that require them.

### React
- Use functional components with hooks (`useState`, `useEffect`, `useCallback`, `useMemo`).
- Avoid external state management libraries unless genuinely warranted; React's built-in `useState` and `useContext` are preferred for hackathon scope.
- Co-locate component files only when there are multiple tightly coupled files to co-locate.

### Naming Conventions
- Standard, descriptive, boring names: `get_user_by_id`, not `fetchUsrData2`.
- Consistency across the codebase takes priority over idiosyncratic stylistic preferences.

---

## 7. Directing AI Agents Checklist

When prompting or tasking an agent to build a module:
1. Provide the **locked contract** (input/output shapes).
2. Explicitly mandate: *"Follow standard Django/DRF/React conventions."*
3. Explicitly mandate: *"Write only what is needed for this contract — no speculative code or extraneous features."*
4. Explicitly mandate: *"Keep within the existing file structure — do not create new files unless the logic genuinely cannot belong anywhere existing."*
5. Provide a one-line description of what **"done"** looks like for the module.
6. Verify output against the Definition of Done before merging.

---

## 8. Definition of Done (Module / Component)

A module or piece of code is done when:
- [ ] Matches its locked contract exactly — no more, no less.
- [ ] Passes its own unit and behavioral tests.
- [ ] Free of dead code, unused imports, or commented-out blocks.
- [ ] Readable and understandable by a teammate within one minute.
- [ ] Follows idiomatic framework patterns, not custom inventions.
