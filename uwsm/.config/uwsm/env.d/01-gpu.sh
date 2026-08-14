#!/usr/bin/env sh
# 01-gpu.sh - GPU-specific environment variables (sourced by uwsm at session start)
#
# These NVIDIA vars must ONLY be set when the proprietary NVIDIA driver is
# actually in use. Setting them on AMD/Intel/nouveau machines breaks VA-API,
# GBM, and GLX, so we gate on the loaded 'nvidia' kernel module.

if command -v lsmod >/dev/null 2>&1 && lsmod | grep -q '^nvidia'; then
    export LIBVA_DRIVER_NAME=nvidia
    export GBM_BACKEND=nvidia-drm
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
fi
