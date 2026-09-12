---
name: ui-guidelines
description: >-
  Provides UI design system specifications, styling standards, and component implementation rules based on Material Design 3 and Tailwind CSS.
  Use this skill whenever designing or implementing frontend UI components, styling screens, selecting typography or colors,
  configuring Tailwind, or verifying visual states and accessibility.
---

# UI Guidelines — CWA Ship Karachi 2026

**Purpose:** Build a clean, minimal, and aesthetically refined user interface based on Material Design 3's structural system, flexible enough to match the emotional tone of any product domain. UI implementation commences only after the UX journey map is finalized.

---

## 1. Technology Stack

- **React + Vite:** Standard, fast, and modern frontend setup.
- **Tailwind CSS:** Utility classes mapped directly to design tokens to prevent arbitrary hardcoded styles.
- **TypeScript (Recommended):** Type definitions synchronized with the backend OpenAPI schema to prevent contract drift.
- **Static Asset Serving:** Built as static assets served by Nginx alongside API routes (single origin, zero CORS overhead).

---

## 2. Locked Structure vs. Adaptive Emotion

The design system separates fixed structural mechanics from emotional styling chosen per product domain.

### A. Locked Structural System (Material Design 3 Basis)
- **Spacing Scale:** Strict 4px base unit (`4`, `8`, `12`, `16`, `24`, `32`, `48`, `64` px). All padding and margin values must come from this scale.
- **Type Scale:** M3 scale steps: `Display`, `Headline`, `Title`, `Body`, `Label` (with `sm`, `md`, `lg` variants).
- **Role-Based Color Slots:** Use semantic color roles rather than hardcoded hex values:
  - `primary`, `secondary`, `tertiary`
  - `surface`, `background`, `error`
  - `-on` variants for text/icons on each surface (e.g., `on-primary`, `on-surface`).
- **Complete Component States:** Every interactive component (buttons, inputs, cards) must implement all 6 states before completion:
  1. Default
  2. Hover
  3. Active / Focused
  4. Disabled
  5. Loading
  6. Error
- **Subtle Elevation:** M3 subtle layering shadows for modals, menus, and dropdowns; never decorative drop-shadows.
- **Unified Iconography:** One consistent icon set throughout the application (Material Symbols).
- **Accessibility Baselines:** Minimum 4.5:1 text contrast ratio, minimum 44x44px interactive tap targets, visible keyboard focus indicators.

### B. Prohibited Design Patterns
- Background gradients or heavy visual noise.
- Animations exceeding 200ms or non-functional decorative motion.
- More than two active accent colors visible simultaneously.
- Unnecessary decorative illustrations that do not assist the user's task.
- Skeuomorphic elements, heavy drop shadows, or textured layers.

### C. Adaptive Emotional Layer (Kickoff Selection)
Configure tokens in `tailwind.config.js` based on product tone:

| Tone Category | Font Feel | Color Direction | Spacing Density |
|---|---|---|---|
| **Trust / Care** (Health, Civic, Finance) | Clean, rounded sans | Cool blues/greens, moderate saturation | Comfortable |
| **Productivity / Utility** (Dashboards, Tools) | Crisp, neutral sans | Cooler neutrals, single confident accent | Compact |
| **Energetic / Social** (Community, Events) | Warm, friendly sans | Warm accent, higher contrast | Comfortable |

---

## 3. Component Implementation Standards

- **Forms:** Inline field validation, clear error messages linked to specific inputs, submit buttons disabled during network requests.
- **Buttons:** Maximum of two button styles per screen (one primary action, one secondary/ghost action).
- **Navigation:** Strictly mirror the steps in the locked UX journey map.
- **State Handling:** Every screen interacting with the backend must handle all four states:
  1. `Loading` (skeleton or spinner)
  2. `Populated` (successful data display)
  3. `Empty` (helpful zero-state guidance)
  4. `Error` (actionable recovery message using the standard response envelope)

---

## 4. Tailwind Configuration Rule

Extend `tailwind.config.js` with semantic tokens and CSS variables rather than using arbitrary inline utility values (`p-[13px]`, `text-[#123456]`):

```javascript
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      colors: {
        primary: 'var(--color-primary)',
        'on-primary': 'var(--color-on-primary)',
        surface: 'var(--color-surface)',
        'on-surface': 'var(--color-on-surface)',
        background: 'var(--color-background)',
        error: 'var(--color-error)',
      },
      spacing: {
        1: '4px',
        2: '8px',
        3: '12px',
        4: '16px',
        6: '24px',
        8: '32px',
        12: '48px',
        16: '64px',
      }
    }
  }
}
```

---

## 5. Definition of Done (UI Component)

A UI component or screen is complete when:
- [ ] Conforms to the locked 4px spacing scale and semantic color roles.
- [ ] All 6 interactive states (default, hover, active, disabled, loading, error) are styled.
- [ ] Loading, Empty, and Error states are implemented for data-fetching views.
- [ ] Accessibility minimums are met (>= 4.5:1 contrast, >= 44px targets, clear focus rings).
- [ ] Transitions are snappy (<= 200ms) with zero gratuitous decorative motion.
