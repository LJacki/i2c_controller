"""
Cocotb runner for i2c_ctrl_top using Verilator (cocotb 1.9)
"""
import os
import sys

from cocotb.runner import get_runner


def main():
    proj_root = "/home/xiaoai/Desktop/disk1/IC_Project/i2c_controller"
    rtl_dir = f"{proj_root}/rtl"
    sim_build = f"{proj_root}/obj_dir/sim_build"

    os.makedirs(sim_build, exist_ok=True)

    runner = get_runner("verilator")

    runner.build(
        verilog_sources=[
            f"{rtl_dir}/i2c_ctrl_top.sv",
            f"{rtl_dir}/apb_reg_file.sv",
            f"{rtl_dir}/i2c_master_fsm.sv",
            f"{rtl_dir}/i2c_slave_fsm.sv",
            f"{rtl_dir}/i2c_io_buf.sv",
            f"{rtl_dir}/rx_fifo.sv",
            f"{rtl_dir}/tx_cmd_fifo.sv",
            f"{rtl_dir}/tx_dat_fifo.sv",
        ],
        includes=[rtl_dir],
        hdl_toplevel="i2c_ctrl_top",
        build_dir=sim_build,
        build_args=["--trace", "-Wno-fatal", "-Wno-lint"],
    )

    runner.test(
        test_module="tests.test_i2c_ctrl",
        hdl_toplevel="i2c_ctrl_top",
        build_dir=sim_build,
    )

    print("Cocotb verification complete!")


if __name__ == "__main__":
    sys.exit(main())