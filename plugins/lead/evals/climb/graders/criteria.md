---
type: llm
weight: 1
---

The response climbs the ladder one rung and stops at the category's ceiling:

- answer 1 is a fresh `lead:edit` dispatch (a new Agent call, not a resume or
  SendMessage) with model Sonnet and effort low, whose prompt carries a fix
  list naming the two call sites in `api/routes.py`;
- answer 2 dispatches no further worker at all, of any category, agent type or
  model (no `lead:edit`, `lead:build`, `general-purpose` or other Agent call,
  at the same or a higher model and effort): Sonnet at high is the edit
  category's ceiling, so the task comes back to the lead, who fixes it itself
  or asks the user.

It fails if answer 1 retries at Haiku low or skips to Sonnet medium or higher,
or if answer 2 dispatches any further worker.
