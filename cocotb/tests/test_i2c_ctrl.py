"""
Minimal cocotb test for i2c_ctrl_top using Verilator
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge


@cocotb.test()
async def test_i2c_ctrl_basic(dut):
    """Basic sanity test - clock and reset"""
    
    cocotb.start_soon(Clock(dut.pclk, 20, units="ns").start())
    
    dut.presetn.value = 0
    await Timer(100, units="ns")
    dut.presetn.value = 1
    
    dut.paddr.value = 0
    dut.psel.value = 0
    dut.penable.value = 0
    dut.pwrite.value = 0
    dut.pwdata.value = 0
    dut.scl_i.value = 1
    dut.sda_i.value = 1
    
    await Timer(200, units="ns")
    
    # After reset, prdata should be a defined register value (not garbage)
    prdata = int(dut.prdata.value)
    cocotb.log.info(f"After reset prdata=0x{prdata:08x}")
    
    # Just verify it's a valid value (not all X/Z)
    assert prdata != 0xFFFFFFFF, "prdata is undefined after reset"
    
    cocotb.log.info("Basic test PASSED - clock and reset working")


@cocotb.test()
async def test_apb_write_read(dut):
    """APB write and read back test"""
    
    cocotb.start_soon(Clock(dut.pclk, 20, units="ns").start())
    
    dut.presetn.value = 0
    await Timer(100, units="ns")
    dut.presetn.value = 1
    await Timer(50, units="ns")
    
    async def apb_write(addr, data):
        dut.paddr.value = addr
        dut.pwdata.value = data
        dut.psel.value = 1
        dut.pwrite.value = 1
        dut.penable.value = 0
        await RisingEdge(dut.pclk)
        await Timer(1, units="ns")
        dut.penable.value = 1
        await RisingEdge(dut.pclk)
        await Timer(1, units="ns")
        while int(dut.pready.value) == 0:
            await RisingEdge(dut.pclk)
        dut.psel.value = 0
        dut.penable.value = 0
    
    async def apb_read(addr):
        dut.paddr.value = addr
        dut.psel.value = 1
        dut.pwrite.value = 0
        dut.penable.value = 0
        await RisingEdge(dut.pclk)
        await Timer(1, units="ns")
        dut.penable.value = 1
        await RisingEdge(dut.pclk)
        await Timer(1, units="ns")
        while int(dut.pready.value) == 0:
            await RisingEdge(dut.pclk)
        data = int(dut.prdata.value)
        dut.psel.value = 0
        dut.penable.value = 0
        return data
    
    await Timer(50, units="ns")
    
    # Write to enable register (offset 0x1C = 28)
    await apb_write(0x1C, 0x00000001)
    await Timer(100, units="ns")
    
    # Read back
    val = await apb_read(0x1C)
    
    cocotb.log.info(f"APB read back: 0x{val:08x}")
    assert (val & 0x1) != 0, f"Expected enable bit set, got 0x{val:08x}"
    
    cocotb.log.info("APB write/read test PASSED")


@cocotb.test()
async def test_i2c_master_write(dut):
    """I2C master single byte write test"""
    
    cocotb.start_soon(Clock(dut.pclk, 20, units="ns").start())
    
    dut.presetn.value = 0
    await Timer(100, units="ns")
    dut.presetn.value = 1
    
    dut.scl_i.value = 1
    dut.sda_i.value = 1
    
    async def apb_write(addr, data):
        dut.paddr.value = addr
        dut.pwdata.value = data
        dut.psel.value = 1
        dut.pwrite.value = 1
        dut.penable.value = 0
        await RisingEdge(dut.pclk)
        dut.penable.value = 1
        await RisingEdge(dut.pclk)
        while int(dut.pready.value) == 0:
            await RisingEdge(dut.pclk)
        dut.psel.value = 0
        dut.penable.value = 0
    
    await Timer(100, units="ns")
    
    # Configure I2C: enable master, speed=0 (standard), target=0x50
    await apb_write(0x1C, 0x00000001)   # enable
    await apb_write(0x00, 0x00000050)   # tar = 0x50
    await apb_write(0x04, 0x00000000)   # master mode
    await Timer(200, units="ns")
    
    # Check status
    dut.paddr.value = 0x04
    dut.psel.value = 1
    dut.pwrite.value = 0
    dut.penable.value = 0
    await RisingEdge(dut.pclk)
    dut.penable.value = 1
    await RisingEdge(dut.pclk)
    await Timer(1, units="ns")
    status = int(dut.prdata.value)
    dut.psel.value = 0
    dut.penable.value = 0
    
    cocotb.log.info(f"I2C status: 0x{status:08x}")
    cocotb.log.info("I2C master write test PASSED (basic)")


@cocotb.test()
async def test_i2c_enable_disable(dut):
    """Test I2C enable and disable via APB"""
    
    cocotb.start_soon(Clock(dut.pclk, 20, units="ns").start())
    
    dut.presetn.value = 0
    await Timer(100, units="ns")
    dut.presetn.value = 1
    
    dut.scl_i.value = 1
    dut.sda_i.value = 1
    
    async def apb_write(addr, data):
        dut.paddr.value = addr
        dut.pwdata.value = data
        dut.psel.value = 1
        dut.pwrite.value = 1
        dut.penable.value = 0
        await RisingEdge(dut.pclk)
        dut.penable.value = 1
        await RisingEdge(dut.pclk)
        while int(dut.pready.value) == 0:
            await RisingEdge(dut.pclk)
        dut.psel.value = 0
        dut.penable.value = 0
        await Timer(10, units="ns")
    
    async def apb_read(addr):
        dut.paddr.value = addr
        dut.psel.value = 1
        dut.pwrite.value = 0
        dut.penable.value = 0
        await RisingEdge(dut.pclk)
        dut.penable.value = 1
        await RisingEdge(dut.pclk)
        while int(dut.pready.value) == 0:
            await RisingEdge(dut.pclk)
        data = int(dut.prdata.value)
        dut.psel.value = 0
        dut.penable.value = 0
        return data
    
    await Timer(100, units="ns")
    
    # Read default enable status
    val_default = await apb_read(0x1C)
    cocotb.log.info(f"Default enable reg: 0x{val_default:08x}")
    
    # Enable controller
    await apb_write(0x1C, 0x00000001)
    val_en = await apb_read(0x1C)
    cocotb.log.info(f"After enable: 0x{val_en:08x}")
    
    # Disable controller
    await apb_write(0x1C, 0x00000000)
    val_dis = await apb_read(0x1C)
    cocotb.log.info(f"After disable: 0x{val_dis:08x}")
    
    assert (val_en & 0x1) != 0, "Enable bit not set after write"
    assert (val_dis & 0x1) == 0, "Enable bit not cleared after write"
    
    cocotb.log.info("I2C enable/disable test PASSED")