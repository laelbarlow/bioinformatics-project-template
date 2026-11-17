# SPDX-FileCopyrightText: 2026 Lael D. Barlow
# SPDX-License-Identifier: MIT

# Starts this environment's R kernel, xeus-r, in place of a Python kernel.
# Zed's REPL, on a project opened over SSH, starts every kernel as
# `python -m ipykernel_launcher`. register-kernel.sh copies this file into the
# rstats environment's site-packages, where that command finds it.

import os
import sys

env = os.path.dirname(os.path.dirname(sys.executable))
xr = os.path.join(env, "bin", "xr")
os.environ["R_HOME"] = os.path.join(env, "lib", "R")
libs = "DYLD_LIBRARY_PATH" if sys.platform == "darwin" else "LD_LIBRARY_PATH"
os.environ[libs] = os.path.join(env, "lib", "R", "lib")
os.execv(xr, [xr, *sys.argv[1:]])
