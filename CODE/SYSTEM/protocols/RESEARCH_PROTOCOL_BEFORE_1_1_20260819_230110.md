# AI_RESEARCH_HUB — RESEARCH PROTOCOL

Version: 1.0
Status: CANONICAL
Scope: All research agents and orchestrators

---

## 1. PURPOSE

This protocol defines the default research behavior of the AI_RESEARCH_HUB.

The objective is to produce research that is:

- evidence-based;
- externally verifiable;
- auditable;
- cumulative;
- reusable;
- resistant to stale or unsupported assumptions.

Existing local knowledge is a starting context, never the boundary of research.

---

## 2. DEFAULT RESEARCH FLOW

For every normal research request, the agent must follow this order:

1. Understand the question and its constraints.

2. Consult INDEX first to discover whether relevant approved knowledge,
   sources, projects, or previous research already exist.

3. Consult only relevant material in KNOWLEDGE.

4. Consult relevant entries in SOURCES and previous RESEARCH when they
   can materially improve the investigation.

5. Perform independent external research when the question requires
   factual, technical, current, scientific, legal, historical, product,
   software, market, or otherwise verifiable information.

6. Compare new evidence with existing local knowledge.

7. Explicitly identify:
   - confirmations;
   - contradictions;
   - outdated information;
   - unresolved uncertainty;
   - inference.

8. Produce the required research artifacts.

9. Never promote research automatically into canonical KNOWLEDGE.

Human or orchestrator approval is required for promotion.

---

## 3. LOCAL KNOWLEDGE RULE

Local material must not be treated as automatically correct merely
because it already exists in the HUB.

Approved KNOWLEDGE may be used as trusted starting context, but factual
claims should still be checked against external evidence when the
research question requires verification or current information.

KNOWLEDGE/pending is not approved canonical knowledge.

Previous RESEARCH is evidence and historical context, not automatically
current truth.

---

## 4. NAVIGATION RULE

Do not recursively read the entire HUB by default.

Use this navigation order:

INDEX
  ↓
relevant KNOWLEDGE
  ↓
relevant SOURCES
  ↓
relevant previous RESEARCH
  ↓
external research

Read only material reasonably relevant to the current question.

---

## 5. EXTERNAL RESEARCH RULE

External research must not be artificially limited by existing local
knowledge.

The agent must remain free to discover:

- newer sources;
- contradictory evidence;
- primary documentation;
- official documentation;
- research papers;
- repositories;
- datasets;
- reputable secondary sources;
- other evidence relevant to the question.

When the user explicitly restricts the allowed sources, that restriction
takes precedence.

If the user explicitly requests local-only or source-only analysis,
external research must not be added unless requested.

---

## 6. SOURCE QUALITY

Prefer evidence in approximately this order when appropriate:

1. primary sources;
2. official documentation;
3. original research papers or datasets;
4. authoritative institutional sources;
5. high-quality secondary analysis;
6. community sources when they provide unique evidence or practical
   information unavailable elsewhere.

Source quality depends on the subject.

Do not use source count as a substitute for source quality.

Do not decide disagreements by majority vote alone.

---

## 7. RECENCY

For information that can change over time, verify the current state.

Examples include:

- software versions;
- documentation;
- APIs;
- laws and regulations;
- prices;
- company roles;
- product specifications;
- security guidance;
- market information.

Older sources may still be useful for historical context but must not be
silently presented as current.

---

## 8. FACT, INFERENCE, AND UNCERTAINTY

The agent must distinguish between:

FACT
Information directly supported by evidence.

INFERENCE
A conclusion derived from evidence but not directly stated by a source.

UNCERTAINTY
A point that could not be established confidently.

CONTRADICTION
A material disagreement between credible sources or between new
evidence and existing HUB knowledge.

These categories must not be silently merged.

---

## 9. AUDITABILITY

Research must preserve observable evidence of the process where the
runner supports it, including:

- question;
- run identifier;
- agent;
- model;
- provider;
- timestamps;
- searches performed;
- URLs or source identifiers;
- observable commands and tool activity;
- errors;
- report;
- source list;
- file hashes.

Do not attempt to store or expose private hidden chain-of-thought.

Auditability means preserving observable method, evidence, actions,
sources, outputs, and conclusions.

---

## 10. WRITE BOUNDARIES

Research agents must write only to the workspace explicitly assigned to
their current run.

Agents must not directly modify:

- INDEX;
- canonical KNOWLEDGE;
- SOURCES registry;
- PROJECTS;
- SYSTEM;
- another agent's workspace;
- previous completed runs.

Infrastructure permissions remain the authoritative security boundary.

Prompt instructions are additional behavior rules, not replacements for
filesystem isolation.

---

## 11. KNOWLEDGE PROMOTION

Research results are not canonical knowledge automatically.

Default lifecycle:

research
  ↓
review
  ↓
cross-check
  ↓
optional debate / re-research
  ↓
human or orchestrator approval
  ↓
promotion candidate
  ↓
KNOWLEDGE

A failed, incomplete, contradictory, or unreviewed run must never be
silently promoted.

---

## 12. MULTI-AGENT RULE

When multiple agents are available, important research should favor:

independent research
  ↓
cross-review
  ↓
targeted re-research of disagreements
  ↓
evidence-based synthesis

Agents should not copy another agent's conclusion before completing
their independent investigation unless the task explicitly requires
collaboration from the beginning.

---

## 13. DEFAULT PRINCIPLE

The permanent operating principle is:

LOCAL KNOWLEDGE IS CONTEXT, NOT A SEARCH BOUNDARY.

The system should become more useful as knowledge accumulates without
becoming trapped by its own previous conclusions.
