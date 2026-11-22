# Local run note

On the laptop the plugin was built on, the eval sandbox refuses Bash, so this
case cannot run there: the setup command and the subagent's commit both need a
shell. It runs in CI with `--allow-tools Bash Write Edit`. Last local attempt,
2026-11-22: not run, for that reason. The other six cases run locally.
