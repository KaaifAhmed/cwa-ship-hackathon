---
name: ux-guidelines
description: >-
  Defines the UX design process, user journey mapping, and interaction design principles.
  Use this skill when defining user flows, designing screens and transitions, establishing primary screen actions,
  planning state feedback, or reviewing usability against user goals.
---

# UX Guidelines — CWA Ship Karachi 2026

**Purpose:** The frontend's singular purpose is to serve the SRS — guiding the user to their objective in the fewest, clearest steps possible. UX design occurs prior to any visual design or coding.

---

## 1. Core UX Principle

Evaluate every design decision against one standard:
> **"Does this get the user to their goal faster and more clearly?"**
Aesthetic considerations are secondary to task clarity and completion speed.

---

## 2. The UX Design Workflow (10–15 Minutes in Phase 2)

Execute this procedure immediately upon completion of the Software Requirements Specification (SRS):

1. **Extract the Primary Journey:**
   - Formulate one concise sentence from the SRS: identify the user, their primary goal, and the minimal sequence to accomplish it.
2. **Enumerate Screens & Steps:**
   - List every discrete screen/view required to fulfill that journey end-to-end. Exclude non-essential screens.
3. **Ruthlessly Prune Steps:**
   - For every step, ask: *Can this step be omitted, merged into another screen, or populated with an intelligent default?* Every step must justify its friction.
4. **Order the Progression:**
   - Entry point → Sequential steps → Goal completion / confirmation.
5. **Enforce One Primary Action per Screen:**
   - Every screen must feature exactly one prominent call-to-action (CTA). If two actions compete for prominence, demote one to secondary status.
6. **Lock the Journey Map:**
   - Finalize and document the flow before proceeding to component architecture or visual styling.

---

## 3. Invariant UX Principles

- **Fewest Clicks to Value:** Minimize unnecessary interaction hurdles.
- **Progressive Disclosure:** Present only the information and inputs required for the immediate step; avoid cluttering single screens with peripheral options.
- **Continuous State Feedback:** Every user action must trigger unambiguous feedback (loading indicator, success confirmation, or descriptive error via the standard envelope). Dead clicks or silent failures are prohibited.
- **Forgiving Interactions:** Support easy recovery (cancel, undo, back navigation) wherever feasible.
- **Accessibility by Default:** Legible type, keyboard navigability, clear focus hierarchy, and adequate tap sizing.

---

## 4. Key Artifact: The Journey Map

The primary deliverable of UX planning is a concise **Journey Map**:
- Numbered sequence of screens and transitions.
- Explicit designation of each screen's single primary action.
- Input data requirements and output feedback per screen.

This artifact provides the foundation for component contracts (Phase 3) and UI styling (Phase 4).

---

## 5. Definition of Done (UX Review)

A UX flow is approved when:
- [ ] The journey accomplishes the primary SRS user goal in the minimum feasible steps.
- [ ] Each screen has exactly one primary action clearly designated.
- [ ] User feedback states (loading, empty, error, success) are specified for all dynamic interactions.
- [ ] Back navigation and error recovery paths are accounted for.
- [ ] The flow is documented and locked before frontend code is generated.
