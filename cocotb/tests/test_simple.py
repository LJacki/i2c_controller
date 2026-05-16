"""
Cocotb Test - i2c_ctrl_top (Python Verification)
Minimal test first to verify VPI connection works
"""
import cocotb
from cocotb.triggers import Timer, RisingEdge
from cocotb.clock import Clock as CocotbClock


@cocotb.test()
async def test_clock_and_reset(dut):
    """Sanity test: clock and reset"""
    cocotb.log.info("=== Cocotb connected! ===")

    # Drive clock
    clk = CocotbClock(dut.pclk, 20, 'ns')
    cocotb.start_soon(clk.start())

    # Reset
    dut.presetn.value = 0
    dut.paddr.value = 0
    dut.psel.value = 0
    dut.penable.value = 0
    dut.pwrite.value = 0
    dut.pwdata.value = 0
    dut.scl_i.value = 1
    dut.sda_i.value = 1

    await Timer(100, 'ns')
    dut.presetn.value = 1
    await Timer(100, 'ns')

    cocotb.log.info("Clock and reset OK")
    cocotb.log.info(f"pready initial value: {dut.pready.value}")


@cocotb.test()
async def test_apb_write_read(dut):
    """Test APB write and read"""
    cocotb.log.info("=== Test APB Write/Read ===")

    clk = CocotbClock(dut.pclk, 20, 'ns')
    cocotb.start_soon(clk.start())

    # Reset
    dut.presetn.value = 0
    yield Timer(100, 'ns')
    dut.presetn.value = 1
    yield Timer(100, 'ns')

    # APB Write: CON register (0x00) = 0x43
    dut.psel.value = 1
    dut.penable.value = 0
    dut.paddr.value = 0
    dut.pwrite.value = 1
    dut.pwdata.value = 0x43

    await RisingEdge(dut.pclk)
    dut.penable.value = 1
    await RisingEdge(dut.pclk)

    # Wait for pready
    while dut.pready.value == 0:
        await RisingEdge(dut.pclk)

    dut.psel.value = 0
    dut.penable.value = 0
    yield Timer(10, 'ns')

    cocotb.log.info("APB write done")

    # APB Read back
    dut.psel.value = 1
    dut.penable.value = 0
    dut.paddr.value = 0
    dut.pwrite.value = 0

    await RisingEdge(dut.pclk)
    dut.penable.value = 1
    await RisingEdge(dut.pclk)

    while dut.pready.value == 0:
        await RisingEdge(dut.pclk)

    data = int(dut.prdata.value)
    dut.psel.value = 0
    dut.penable.value = 0

    cocotb.log.info(f"APB read back: 0x{data:08x}")
    assert data == 0x43, f"Expected 0x43, got 0x{data:08x}"
    cocotb.log.info("APB Write/Read: PASS")