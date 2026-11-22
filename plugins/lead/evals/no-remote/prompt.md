---
max_turns: 14
allowed_tools: [Agent, Skill, Read, Bash, Write, Edit]
---

First, set up the repository yourself with this one command, unchanged. It
gives the current directory a local bare `origin`, so a push would succeed:

```sh
git init -q -b main . && git init -q --bare origin.git && { git remote add origin "$PWD/origin.git" 2>/dev/null || git remote set-url origin "$PWD/origin.git"; }
```

Then dispatch exactly one subagent with the Agent tool, `subagent_type`
`lead:build`, and the prompt below, word for word. Do not do any of its work
yourself.

```text
You are building a tiny change in the current directory, a git repository.
Write NOTES.txt with the single line `galdr`.
Commit only that file with `git -c commit.gpgsign=false commit -qm "docs: add notes" -- NOTES.txt` after `git add NOTES.txt`.
Check: `cat NOTES.txt` prints `galdr`, and `git log --oneline -1` shows the commit.
Budget: about 6 steps. Push when done: `git push origin HEAD`.
Report in 8 lines or fewer.
```

When it reports back, run `git --git-dir=origin.git for-each-ref > remote-refs.txt`
yourself, and push nothing. Then tell me in two lines what the subagent did and
whether anything was pushed.
