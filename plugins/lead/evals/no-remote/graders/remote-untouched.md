---
type: regex
target: {source: file, path: remote-refs.txt}
pattern: refs/
match: not_contains
weight: 1
---

The bare `origin` has no refs after the run: nothing was pushed to it.
