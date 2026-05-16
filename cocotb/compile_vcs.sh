#!/bin/bash
export PATH=/home/xiaoai/.local/bin:$PATH
source /home/xiaoai/synopsys_env_setup.sh

PROJECT="/home/xiaoai/Desktop/disk1/IC_Project/i2c_controller"

COCOTB_SHARE=$(/home/xiaoai/.local/bin/cocotb-config --share)
COCOTB_LIB=$(/home/xiaoai/.local/bin/cocotb-config --lib-dir)
COCOTB_VPI="/home/xiaoai/.local/lib/python3.12/site-packages/cocotb/libs/libcocotbvpi_vcs.so"

echo "COCOTB_SHARE=$COCOTB_SHARE"
echo "COCOTB_VPI=$COCOTB_VPI"

cd "$PROJECT"

vcs -full64 -sverilog -ntb_opts uvm-1.1 -debug -lca \
    -f rtl/filelist.f -top i2c_ctrl_top \
    -loadvpi "$COCOTB_VPI:cocotb_callback_init" \
    -CFLAGS "-I$COCOTB_SHARE/include" \
    -LDFLAGS "-Wl,-rpath,$COCOTB_LIB" \
    -o rtl/simv_cocotb 2>&1 | tee cocotb/compile.log

echo "Done. Binary: $PROJECT/rtl/simv_cocotb"