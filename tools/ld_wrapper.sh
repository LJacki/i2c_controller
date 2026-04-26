#!/bin/bash
# ld wrapper: injects --wrap=pthread_yield to fix Ubuntu 24.04/glibc 2.39 link issue
# with VCS O-2018.09-SP2 vcs_save_restore_new.o
args=()
new_args=()
found_lpthread=0
for arg in "$@"; do
    if [[ "$found_lpthread" == "0" && "$arg" == "-lpthread" ]]; then
        new_args+=("--wrap=pthread_yield")
        new_args+=("/home/xiaoai/lib64_compat/libpthread_wrap.so")
        found_lpthread=1
    fi
    new_args+=("$arg")
done
exec /usr/bin/ld "${new_args[@]}"
