#!/bin/bash
# Verdi 波形查看启动脚本
# 使用方法:
#   bash tools/verdi.sh                # 打开最近一次的 wave.vcd
#   bash tools/verdi.sh wave.vcd       # 打开指定波形文件
#   bash tools/verdi.sh -rtl           # 打开 RTL 源码 + 信号

PROJECT_ROOT=/home/xiaoai/Desktop/disk1/IC_Project/i2c_controller
cd "$PROJECT_ROOT"

source /home/xiaoai/synopsys_env_setup.sh
export VERDI_HOME=/eda/synopsys/verdi/2018.9/verdi/Verdi_O-2018.09-SP2

WAVE_FILE=""
USE_RTL=0

if [ "$1" == "-rtl" ]; then
    USE_RTL=1
elif [ -n "$1" ]; then
    WAVE_FILE="$1"
elif [ -f "sim/wave.vcd" ]; then
    WAVE_FILE="sim/wave.vcd"
elif [ -f "sim/simv.wlf" ]; then
    WAVE_FILE="sim/simv.wlf"
else
    echo "Usage: $0 [-rtl | <wavefile>]"
    echo "  -rtl         : 打开 RTL 源码 + 信号列表"
    echo "  <wavefile>   : 打开指定波形文件 (默认: sim/wave.vcd)"
    echo "  (无参数)      : 打开 sim/wave.vcd"
    exit 1
fi

if [ $USE_RTL -eq 1 ]; then
    echo "=== Opening RTL source + signals ==="
    $VERDI_HOME/bin/verdi \
        -f rtl/filelist.f \
        -ssverilog \
        -input verdi.rc \
        -ss &
else
    echo "=== Opening waveform: $WAVE_FILE ==="
    $VERDI_HOME/bin/verdi \
        $WAVE_FILE \
        -input verdi.rc \
        -ss &
fi

echo "Verdi started in background"
