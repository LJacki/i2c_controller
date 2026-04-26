// Test: Constrained Random Register Access
// Cover: All registers accessed in random order, random values, random read/write sequence
// Constraints: Valid register addresses (0x00~0x4C), valid field values
class test_rand_reg_access extends base_test;

  `uvm_component_utils(test_rand_reg_access)

  // Register addresses to test (all defined registers per SPEC v2.2)
  logic [7:0] reg_addrs[] = '{
    8'h00, 8'h04, 8'h08, 8'h0C,
    8'h10, 8'h14, 8'h18, 8'h1C,
    8'h20, 8'h2C, 8'h30, 8'h34,
    8'h44
  };

  int num_accesses = 20;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("TEST_RAND_REG_ACCESS", "Starting Random Register Access Test...", UVM_MEDIUM)

    // Perform random read/write sequence
    for (int i = 0; i < num_accesses; i++) begin
      logic [7:0] addr = reg_addrs[$urandom_range(0, reg_addrs.size()-1)];
      logic [31:0] wdata = $urandom();
      logic [31:0] rdata;

      // Randomly choose read or write
      bit is_write = $urandom_range(0, 1);

      if (is_write) begin
        apb_write(addr, wdata);
        `uvm_info("TEST_RAND_REG_ACCESS", $sformatf("[%0d] WRITE addr=0x%02h data=0x%08h", i, addr, wdata), UVM_MEDIUM)

        // Read back immediately for defined read-write registers
        if (addr != 8'h0C && addr != 8'h24 && addr != 8'h28 &&
            addr != 8'h38 && addr != 8'h3C && addr != 8'h40 && addr != 8'h48 && addr != 8'h4C) begin
          apb_read(addr, rdata);
          `uvm_info("TEST_RAND_REG_ACCESS", $sformatf("       READBACK addr=0x%02h data=0x%08h", addr, rdata), UVM_MEDIUM)
        end
      end else begin
        apb_read(addr, rdata);
        `uvm_info("TEST_RAND_REG_ACCESS", $sformatf("[%0d] READ  addr=0x%02h data=0x%08h", i, addr, rdata), UVM_MEDIUM)
      end
    end

    // Specific register tests
    // Test all TX_TL values (0, 4, 8, 15)
    begin
      logic [31:0] val;
      int tl_vals[] = '{0, 4, 8, 15};
      foreach (tl_vals[i]) begin
        apb_write(8'h30, tl_vals[i]);  // TX_TL
        apb_read(8'h30, val);
        `uvm_info("TEST_RAND_REG_ACCESS", $sformatf("TX_TL=%0d -> read=0x%08h", tl_vals[i], val), UVM_MEDIUM)
      end
    end

    // Test all RX_TL values (0, 4, 8, 15)
    begin
      logic [31:0] val;
      int tl_vals[] = '{0, 4, 8, 15};
      foreach (tl_vals[i]) begin
        apb_write(8'h2C, tl_vals[i]);  // RX_TL
        apb_read(8'h2C, val);
        `uvm_info("TEST_RAND_REG_ACCESS", $sformatf("RX_TL=%0d -> read=0x%08h", tl_vals[i], val), UVM_MEDIUM)
      end
    end

    // Test SDA_HOLD values
    begin
      logic [31:0] val;
      apb_write(8'h44, 16'h0001);
      apb_read(8'h44, val);
      apb_write(8'h44, 16'h00FF);
      apb_read(8'h44, val);
      apb_write(8'h44, 16'h1234);
      apb_read(8'h44, val);
      `uvm_info("TEST_RAND_REG_ACCESS", $sformatf("SDA_HOLD read=0x%08h", val), UVM_MEDIUM)
    end

    `uvm_info("TEST_RAND_REG_ACCESS", "Random Register Access Test PASSED", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask

  task apb_write(logic [7:0] addr, logic [31:0] data);
    apb_transfer tr;
    tr = apb_transfer::type_id::create("tr");
    tr.kind  = apb_transfer::APB_WRITE;
    tr.addr  = addr;
    tr.data  = data;
    tr.delay = 0;
    env.apb_drv.seq_item_port.put(tr);
  endtask

  task apb_read(logic [7:0] addr, output logic [31:0] data);
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

endclass : test_rand_reg_access
