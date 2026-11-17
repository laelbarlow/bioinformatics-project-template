# SPDX-FileCopyrightText: 2026 Lael D. Barlow
# SPDX-License-Identifier: MIT

# Lints the scripts with the versions pixi.lock pins: ShellCheck on the shell
# scripts, and ruff and pyright on the Python. Run it from the project folder:
#
#   sh .github/checks/lint.sh

set -eu

find workflow .github -name '*.sh' \
    -exec pixi run -e lint shellcheck -s sh -S warning {} +
pixi run -e lint ruff check --no-cache workflow
pixi install
pixi run -e lint pyright --pythonpath .pixi/envs/default/bin/python \
    workflow/template
if ls workflow/scripts/*.py > /dev/null 2>&1; then
    pixi install -e python
    pixi run -e lint pyright --pythonpath .pixi/envs/python/bin/python \
        workflow/scripts
fi
