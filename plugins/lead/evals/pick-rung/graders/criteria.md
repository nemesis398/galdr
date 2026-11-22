---
type: llm
weight: 1
---

The response tags the five tasks like this:

1. scout at rung 1: Haiku, low effort;
2. edit at rung 1: Haiku, low effort;
3. build at rung 3: Sonnet, medium effort;
4. build at rung 5: Opus, high effort;
5. build at rung 5: Opus, high effort.

Category names and rung numbers must match; the model and effort must match
for each. Any task with a different category, start rung, model or effort
fails the case.
