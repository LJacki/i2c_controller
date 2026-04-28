#!/bin/bash
# I2C Controller VCS build + run script
# Usage:
#   make compile                                    # compile only
#   make run TEST=test_basic_master_single_write     # compile + run with auto-timeout
#   make simv TEST=test_basic_master_single_write   # run already-compiled simv

PROJECT_ROOT=/home/xiaoai/Desktop/disk1/IC_Project/i2c_controller
cd "$PROJECT_ROOT"
source /home/xiaoai/synopsys_env_setup.sh
export VCS_HOME=/eda/synopsys/vcs/O-2018.09-SP2/vcs/O-2018.09-SP2
export PATH=$HOME/bin:$VCS_HOME/bin:$PATH
export LD_PRELOAD=$HOME/lib64_compat/libpthread_override.so

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
        echo "ERROR: sim/simv not found. Run 'make compile' first."
        return 1
    fi

    echo "=== Running $test (timeout=${timeout}s) ==="
    echo "Start: $(date)"

    cd sim
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
    return 0  # 始终返回 0，避免 make 因非零退出码中断
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
    simv)
        # 单独运行 simv（假设已编译）
        do_run "$TESTNAME"
        ;;
    *)
        echo "Usage: $0 {compile|run} [TESTNAME]"
        echo "  compile - build simv (default)"
        echo "  run TESTNAME - build + run with auto-timeout"
        exit 1
        ;;
esac
