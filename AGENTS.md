# galdr: agent rules

galdr is a public marketplace of Claude Code plugins. Keep it that way.

- **Public boundary.** Nothing personal, private or local goes into the tree or its
  history: no private hostnames, paths, keys or project names, and no user's name
  in a description. Descriptions say "the user". Config comes only from `<NAME>_CONFIG`
  or `${XDG_CONFIG_HOME:-~/.config}/<name>/config.json`.
- **Em dash.** None in any file. CI (`em-dash` job) fails on one. Use a comma, a
  colon, parentheses or two sentences.
- **Leaves are pinned, never copied in.** A leaf plugin is a separate repository,
  referenced from `.claude-plugin/marketplace.json` by a tag or a commit sha. Do not
  vendor its files here.
- **Commits.** Conventional Commits, signed as usual.
- **Checks before a commit.** `claude plugin validate` on the marketplace and on each
  plugin, markdownlint, ShellCheck, the hook tests, and the em-dash check.
