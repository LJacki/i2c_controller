// Test: Interrupt STOP_DET (STOP condition detection)
// Cover: STOP_DET (bit 8), STP_DET_IF_MASTER_ACTIVE, bus event detection
class test_interrupt_stop_det extends base_test;

  `uvm_component_utils(test_interrupt_stop_det)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    bit [31:0] raw_intr;
    bit [31:0] intr_stat;
    bit [31:0] raw_intr2;
    phase.raise_objection(this);
    `uvm_info("TEST_INTERRUPT_STOP_DET", "Starting STOP_DET Interrupt Test...", UVM_MEDIUM)

    // Unmask STOP_DET interrupt (INTR_MASK[8] = 0 -> enabled)
    apb_write(8'h20, 32'hFDF);  // Mask all except bit 8 (M_STP_DET=0 -> enabled)

    // CON: MASTER_MODE=1, SPEED=Fast, RESTART_EN=1, SLAVE_DISABLE=1, STOP_DET_IF_MASTER_ACTIVE=1
    apb_write(8'h00, 12'h19B);  // Add STOP_DET_IF_MASTER_ACTIVE=1

    // Configure Master
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // Execute a complete write transaction
    apb_write(8'h0C, {24'b0, 8'h77});  // 1 byte write -> STOP

    #50us;

    // Check RAW_INTR_STAT bit 8 (R_STP_DET)
    apb_read(8'h28, raw_intr);
    `uvm_info("TEST_INTERRUPT_STOP_DET", $sformatf("RAW_INTR_STAT=0x%08h (bit8=STP_DET)", raw_intr), UVM_MEDIUM)

    // Check INTR_STAT bit 8 (I_STP_DET, post-mask)
    apb_read(8'h24, intr_stat);
    `uvm_info("TEST_INTERRUPT_STOP_DET", $sformatf("INTR_STAT=0x%08h", intr_stat), UVM_MEDIUM)

    // Also test with slave mode: use I2C BFM to send STOP to slave
    // Configure DUT as slave
    apb_write(8'h08, {25'b0, 7'h3C});  // SAR=0x3C
    apb_write(8'h00, 12'h04);  // MASTER_MODE=0, SLAVE_DISABLE=0
    apb_write(8'h34, 32'h1);   // ENABLE=1

    fork
      begin
        i2c_transfer tr;
        tr = i2c_transfer::type_id::create("tr");
        tr.kind = i2c_transfer::I2C_WRITE;
        tr.addr = 7'h3C;
        tr.data = '{8'h88};
        tr.last_cmd = 1'b0;
        env.i2c_master.seq_item_port.put(tr);
      end
    join_none

    #50us;

    // Check STOP_DET again after slave transaction
    apb_read(8'h28, raw_intr2);
    `uvm_info("TEST_INTERRUPT_STOP_DET", $sformatf("RAW_INTR_STAT after slave STOP=0x%08h", raw_intr2), UVM_MEDIUM)

    `uvm_info("TEST_INTERRUPT_STOP_DET", "STOP_DET interrupt test completed", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask

  task apb_write(bit [7:0] addr, bit [31:0] data);
    apb_transfer tr;
    tr = apb_transfer::type_id::create("tr");
    tr.kind  = apb_transfer::APB_WRITE;
    tr.addr  = addr;
    tr.data  = data;
    tr.delay = 0;
    env.apb_drv.seq_item_port.put(tr);
  endtask

  task apb_read(bit [7:0] addr, output bit [31:0] data);
    apb_transfer tr;
    tr = apb_transfer::type_id::create("tr");
    tr.kind = apb_transfer::APB_READ;
    tr.addr = addr;
    tr.data = 0;
    tr.delay = 0;
    env.apb_drv.seq_item_port.put(tr);
    #1us;
    data = tr.data;
  endtask

endclass : test_interrupt_stop_det
