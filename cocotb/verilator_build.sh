#!/bin/bash
export PATH=/home/xiaoai/.local/bin:$PATH

PROJECT="/home/xiaoai/Desktop/disk1/IC_Project/i2c_controller"
RTL_DIR="$PROJECT/rtl"
BUILD_DIR="$PROJECT/cocotb/build"

mkdir -p "$BUILD_DIR"
cd "$PROJECT"

echo "=== Verilator + Cocotb Build ==="

# All RTL files are actually .sv (not .v)
verilator --cc \
    -Wall \
    --prefix Vcocotb \
    --vpi \
    -I"$RTL_DIR" \
    -CFLAGS "-I$(/home/xiaoai/.local/bin/cocotb-config --share)/include" \
    -LDFLAGS "-Wl,-rpath,$(/home/xiaoai/.local/bin/cocotb-config --lib-dir)" \
    $RTL_DIR/i2c_ctrl_top.sv \
    $RTL_DIR/apb_reg_file.sv \
    $RTL_DIR/i2c_master_fsm.sv \
    $RTL_DIR/i2c_slave_fsm.sv \
    $RTL_DIR/i2c_io_buf.sv \
    $RTL_DIR/rx_fifo.sv \
    $RTL_DIR/tx_cmd_fifo.sv \
    $RTL_DIR/tx_dat_fifo.sv \
    --top-module i2c_ctrl_top \
    2>&1 | tee cocotb/build/compile.log

echo "=== Verilator CC done ==="
if [ -d obj_dir ]; then
    ls -la obj_dir/Vcocotb*/ | head -5
    echo "Building..."
    cd obj_dir/Vcocotb*
    make -j$(nproc) 2>&1 | tail -5
    echo "Build complete: $(ls -la Vcocotb* 2>/dev/null | head -3)"
else
    echo "No obj_dir - build failed"
fi