#!/bin/bash
set -e
PROJECT_ROOT=/home/xiaoai/Desktop/disk1/IC_Project/i2c_controller
cd "$PROJECT_ROOT"
source /home/xiaoai/synopsys_env_setup.sh
export VCS_HOME=/eda/synopsys/vcs/O-2018.09-SP2/vcs/O-2018.09-SP2
export PATH=/home/xiaoai/bin:$VCS_HOME/bin:$PATH
export LD_PRELOAD=/home/xiaoai/lib64_compat/libpthread_override.so
rm -rf sim/simv* sim/csrc sim/DVEfiles sim/*.log sim/simv.vdb
mkdir -p sim
echo "=== Compiling I2C Controller with I2C Bus Monitor ==="
echo "Start: $(date)"
vcs -sverilog   -f rtl/filelist.f   -f tb/uvm/filelist.f   -ntb_opts uvm-1.1   -cm line+cond+fsm+branch+tgl   -cm_dir sim/simv.vdb   -full64   -timescale=1ns/1ps   -top tb_top   -o sim/simv   2>&1 | tee sim/compile.log
echo "End: $(date)"
exit ${PIPESTATUS[0]}
