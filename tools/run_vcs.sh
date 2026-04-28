#!/bin/bash
# I2C Controller VCS build + run script
# Usage:
#   bash tools/run_vcs.sh compile                          # compile only
#   bash tools/run_vcs.sh run test_basic_master_single_write  # compile + run with auto-timeout

PROJECT_ROOT=/home/xiaoai/Desktop/disk1/IC_Project/i2c_controller
cd "$PROJECT_ROOT"
source /home/xiaoai/synopsys_env_setup.sh

# Runtime: use g++ wrapper to inject -L (for link-time pthread_yield)
export PATH=$HOME/bin:$VCS_HOME/bin:$PATH
# Compile: unset LD_PRELOAD to avoid VCS tool crashes (pthread_yield via g++ wrapper)
unset LD_PRELOAD

# ============================================================
# Timeout estimation based on test name patterns
# ============================================================
estimate_timeout() {
    local test=$1
    case "$test" in
        *random*|*stress*|*duration*)
            echo 300  ;;  # 5 min for random/stress tests
        *basic*|*single*|*simple*|*short*)
            echo 60   ;;  # 1 min for basic tests
        *extended*|*long*)
            echo 180  ;;  # 3 min for extended tests
        *)
            echo 90   ;;  # default 90s
    esac
}

# ============================================================
# Build (compile only)
# ============================================================
do_compile() {
    echo "=== Compiling I2C Controller ==="
    echo "Start: $(date)"
    rm -rf sim/simv* sim/csrc sim/DVEfiles sim/*.log sim/simv.vdb
    mkdir -p sim
    vcs -sverilog \
        -f rtl/filelist.f \
        -f tb/uvm/filelist.f \
        -ntb_opts uvm-1.1 \
        -cm line+cond+fsm+branch+tgl \
        -cm_dir sim/simv.vdb \
        -full64 \
        -timescale=1ns/1ps \
        -top tb_top \
        -o sim/simv \
        2>&1 | tee sim/compile.log
    local status=${PIPESTATUS[0]}
    echo "End: $(date) - exit $status"
    return $status
}

# ============================================================
# Run simulation with auto-timeout
# ============================================================
do_run() {
    local test=${1:-test_basic_master_single_write}
    local timeout=$(estimate_timeout "$test")
    local logfile="sim/${test}.log"

    if [ ! -x sim/simv ]; then
        echo "ERROR: sim/simv not found. Run 'do_compile' first."
        return 1
    fi

    echo "=== Running $test (timeout=${timeout}s) ==="
    echo "Start: $(date)"

    # Runtime: LD_LIBRARY_PATH so loader finds libpthread.so (symlink to thin stub)
    cd sim
    LD_LIBRARY_PATH=$HOME/lib64_compat:$LD_LIBRARY_PATH \
        timeout $timeout ./simv \
        +vcs+lic+wait \
        +UVM_TESTNAME=$test \
        -l "$logfile"
    local status=$?
    cd ..

    if [ $status -eq 139 ] || [ $status -eq 137 ]; then
        echo "WARNING: Simulation timed out after ${timeout}s - killed"
    elif [ $status -ne 0 ]; then
        echo "WARNING: Simulation exited with code $status"
    else
        echo "Simulation completed normally"
    fi
    echo "End: $(date) - exit $status"
    return 0
}

# ============================================================
# Entry point
# ============================================================
ACTION=${1:-compile}
TESTNAME=${2:-test_basic_master_single_write}

case "$ACTION" in
    compile)
        do_compile
        ;;
    run)
        do_run "$TESTNAME"
        ;;
    *)
        echo "Usage: $0 {compile|run} [TESTNAME]"
        echo "  compile - build simv (default)"
        echo "  run TESTNAME - build + run with auto-timeout"
        exit 1
        ;;
esac
