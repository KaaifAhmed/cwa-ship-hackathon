---
name: testing-guidelines
description: >-
  Guides the testing strategy, lightweight TDD workflow, and test implementation across unit, component, and integration levels.
  Use this skill whenever writing tests, validating API endpoints or business logic, verifying contract compliance,
  or preparing automated checks for CI.
---

# Testing Guidelines — CWA Ship Karachi 2026

**Purpose:** Prove the system works reliably at every level without encumbering development with unmaintainable test infrastructure. Minimal, meaningful, and understandable tests beat exhaustive, brittle test suites.

---

## 1. Testing Philosophy

- **Lightweight TDD:** For each module in a component's build sequence, write a concise test defining expected behavior *before* (or alongside) implementing the module. The test serves as the specification.
- **Test What Matters:** Cover contract inputs/outputs and failure paths that could realistically break a demo or production flow. Avoid chasing 100% vanity coverage.
- **Do Not Test Framework Internals:** Trust Django's ORM, DRF machinery, and React's rendering engine. Test *your* custom logic and endpoint behavior, not the framework.
- **Readable Over Sophisticated:** Tests must read like plain behavioral descriptions. A teammate should understand the expectation from the test name and body within seconds.

---

## 2. TDD Workflow (Per Module)

1. **Review the contract slice:** (e.g., `POST /auth/login` with valid credentials yields JWT and 200; invalid credentials yield 401).
2. **Write one test per behavior:** Name the test explicitly after the behavior being checked.
3. **Implement to pass:** Write the minimal code required to satisfy the test.
4. **Iterate module by module:** Avoid batching tests at the end of the project.

---

## 3. Scope: What to Test vs. What Not to Test

### What to Test
- **Contract Compliance:** Given valid input, does the endpoint return the correct shape and status code?
- **Core Business Logic:** The domain rules for which the module exists (e.g., expired tokens are rejected, quotas are enforced).
- **Known Failure Paths:** Common error conditions (invalid input, missing authentication headers, missing resources) matching the standard error envelope.

### What Not to Test
- Framework internals (e.g., confirming Django saves a row to SQLite/Postgres).
- Unrealistic edge cases with negligible probability in actual usage.
- Pixel-level frontend layout (interaction smoke tests like "form submit calls endpoint" suffice).

---

## 4. Test Levels & Tooling

| Level | Scope | Execution Point | Tooling |
|---|---|---|---|
| **Unit** | Individual function or isolated module logic | Phase 4–5 (as each module is built) | Django `TestCase` / `pytest-django` |
| **Component** | Service endpoints in isolation | End of Phase 5 | DRF `APIClient` |
| **Integration / System** | End-to-end calls across services via Gateway | Phase 6 | `docker compose up` + E2E verification script / Postman |

> Keep testing focused on these three tiers. Avoid complex load testing or bloated CI matrices — a clean, green CI run on push demonstrates production discipline.

---

## 5. Rules for Writing Tests

- **One behavior per test:** `test_login_with_valid_credentials_returns_token` and `test_login_with_invalid_password_returns_401` — avoid bloated multi-assertion tests that test disparate concerns.
- **Minimal mocking:** Only mock genuinely external dependencies (external third-party APIs, LLM calls, external microservices). Never mock the internal logic of the component under test.
- **Use built-in fixtures and clients:** Rely on standard Django `APIClient` and test fixtures without overengineering custom test factories.
- **Independent tests:** Ensure tests do not rely on side-effects or execution order of other tests.

---

## 6. Directing AI Agents for Testing

When directing an AI agent to build a feature:
1. Provide the specific behavior to satisfy from the locked contract.
2. Request the test first: *"Write a test checking that endpoint X returns Y given input Z."*
3. Prompt for the minimal implementation that makes the test pass.
4. Inspect the test name and assertions: ensure it verifies genuine contract behavior rather than trivial framework mechanics.

---

## 7. Definition of Done (Testing Bar)

A component passes the quality bar when:
- [ ] Every contract endpoint has at least one test for the primary success case and one for the primary failure case.
- [ ] All tests pass cleanly both locally and in CI.
- [ ] Test function names clearly explain what is being verified without needing to inspect implementation details.
- [ ] No test depends on the execution state or side effects of preceding tests.
