# SPDX-FileCopyrightText: 2026 Lael D. Barlow
# SPDX-License-Identifier: MIT

# Register this project's rstats environment as a Jupyter kernel, so that an
# editor's console (Zed's REPL, JupyterLab's console) runs the R in
# .pixi/envs/rstats: the same R, with the same packages, that a rule runs with
# `pixi run -e rstats Rscript`. For Zed over SSH, which ignores registered
# kernels, it also copies ipykernel_launcher.py into the environment.
#
#     pixi run -e rstats kernel
#
# The kernel is named after the project folder. Run this again if the folder
# is moved, because the kernel file holds the folder's absolute path, and
# after the environment is reinstalled.

set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
env="$root/.pixi/envs/rstats"
name=$(basename "$root")

if [ ! -x "$env/bin/xr" ]; then
    echo "$env/bin/xr is missing: install the environment first, with" >&2
    echo "    pixi install -e rstats" >&2
    exit 1
fi

case $(uname) in
    Darwin)
        kernels="$HOME/Library/Jupyter/kernels"
        library_path=DYLD_LIBRARY_PATH
        ;;
    *)
        kernels="$HOME/.local/share/jupyter/kernels"
        library_path=LD_LIBRARY_PATH
        ;;
esac

dir="$kernels/$name-r"
mkdir -p "$dir"
cat > "$dir/kernel.json" <<KERNEL
{
  "display_name": "R ($name)",
  "argv": ["$env/bin/xr", "-f", "{connection_file}"],
  "language": "R",
  "env": {
    "R_HOME": "$env/lib/R",
    "$library_path": "$env/lib/R/lib"
  }
}
KERNEL

echo "Registered the kernel \"R ($name)\" in $dir"

site=$("$env/bin/python" -c 'import sysconfig; print(sysconfig.get_path("purelib"))')
cp "$root/workflow/template/ipykernel_launcher.py" "$site/ipykernel_launcher.py"
echo "Copied ipykernel_launcher.py into $site, for Zed over SSH"
