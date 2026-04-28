#!/bin/bash
set -e
PROJECT_ROOT=/home/xiaoai/Desktop/disk1/IC_Project/i2c_controller
cd "$PROJECT_ROOT"
source /home/xiaoai/synopsys_env_setup.sh
export VCS_HOME=/eda/synopsys/vcs/O-2018.09-SP2/vcs/O-2018.09-SP2
export PATH=/home/xiaoai/bin:$VCS_HOME/bin:$PATH
export LD_PRELOAD=/home/xiaoai/lib64_compat/libpthread_override.so

echo "=== Compiling I2C Controller with FIXED RTL ==="
echo "Start: $(date)"
cd "$PROJECT_ROOT"

rm -rf sim/simv* sim/csrc sim/DVEfiles sim/*.log sim/uhdv* sim/merge.vdb sim/merge_report

vcs -sverilog \
    -f rtl/filelist.f \
    -f tb/uvm/filelist.f \
    -ntb_opts uvm-1.1 \
    -cm line+cond+fsm+branch+tgl \
    -full64 \
    -timescale=1ns/1ps \
    -top tb_top \
    -o sim/simv \
    2>&1 | tee sim/compile.log

COMPILE_OK=$?
echo "Compile exit: $COMPILE_OK"
if [ $COMPILE_OK -ne 0 ]; then
    echo "COMPILE FAILED"
    tail -30 sim/compile.log
    exit 1
fi

# Test list
TESTS=(
    test_basic_master_single_write
    test_basic_master_burst_write
    test_basic_master_single_read
    test_basic_master_burst_read
    test_basic_master_repeated_start
    test_basic_master_addr_nack
    test_basic_master_data_nack
    test_basic_slave_receive
    test_basic_slave_transmit
    test_basic_slave_addr_no_match
    test_interrupt_rx_full
    test_interrupt_tx_empty
    test_interrupt_tx_abrt
    test_interrupt_stop_det
    test_reg_con_write_read
    test_reg_tar_sar
    test_reg_hcnt_lcnt_speed
    test_reg_enable_abort
    test_reg_undefined_addr
    test_rand_master_write
    test_rand_master_read
    test_rand_slave_receive
    test_rand_reg_access
    test_rand_interrupt_mask
)

PASS=0
FAIL=0

# Run each test and save coverage DB
cd "$PROJECT_ROOT/sim"
for i in "${!TESTS[@]}"; do
    TEST="${TESTS[$i]}"
    TEST_NUM=$(printf "%02d" $i)
    echo "=== Running [$TEST_NUM] $TEST ==="

    ./simv +UVM_TESTNAME=$TEST +vcs+lic+wait -l ${TEST}.log 2>&1 | tail -5

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo "[PASS] $TEST"
        PASS=$((PASS+1))
        mv simv.vdb cov/test_${TEST_NUM}.vdb 2>/dev/null || true
        rm -rf simv.vdb
    else
        echo "[FAIL] $TEST"
        FAIL=$((FAIL+1))
    fi
done

echo ""
echo "=== Regression Results: $PASS PASS, $FAIL FAIL ==="

# Merge coverage
cd "$PROJECT_ROOT/sim/cov"
echo "=== Merging coverage ==="
urg -format text -dir test_*.vdb -report merge_report 2>&1 | tail -10
cat merge_report/dashboard.txt
echo ""
echo "=== master_fsm coverage ==="
grep -A3 "u_master_fsm" merge_report/hierarchy.txt
