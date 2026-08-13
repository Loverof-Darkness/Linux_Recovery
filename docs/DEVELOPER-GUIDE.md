# Developer guide

Source the program only through `devil`; it sets strict Bash options before importing modules. Modules may rely on application globals declared by `core/bootstrap.sh`, but must avoid executing actions at import time.

Diagnostic functions must never mount, unlock, write EFI variables, invoke package managers, or modify boot configuration. Mutating functions must call `require_root`, back up the exact target before a change, call `confirm`, and use `run_action` so `--dry-run` and `--test` remain trustworthy.

Run `bash tests/smoke.sh` after edits. If ShellCheck is available, run `shellcheck devil run.sh install.sh uninstall.sh core/*.sh modules/*.sh ui/*.sh`.
