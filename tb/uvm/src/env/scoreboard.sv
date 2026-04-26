// Scoreboard - compares APB transactions against I2C bus activity
class scoreboard extends uvm_scoreboard;

  // TLM FIFOs to receive transactions from monitors
  uvm_tlm_analysis_fifo #(apb_transfer) apb_fifo;
  uvm_tlm_analysis_fifo #(i2c_transfer) i2c_fifo;

  // Expected data queue (from APB writes to DATA_CMD)
  logic [7:0] expected_data_queue[$];

  // Received data queue (from I2C reads)
  logic [7:0] received_data_queue[$];

  // Match counter
  int mismatch_count = 0;
  int match_count = 0;

  `uvm_component_utils(scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    apb_fifo  = new("apb_fifo", this);
    i2c_fifo  = new("i2c_fifo", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    fork
      process_apb_fifo();
      process_i2c_fifo();
    join
  endtask

  // Process APB transactions
  task process_apb_fifo();
        reg [7:0] data_byte = tr.data[7:0];
        logic       cmd_bit   = tr.data[8];  // CMD=0 write, CMD=1 read
          reg [7:0] rcvd = received_data_queue.pop_front();
    apb_transfer tr;
    forever begin
      apb_fifo.get(tr);
      if (tr.kind == apb_transfer::APB_WRITE && tr.addr == 8'h0C) begin
        // DATA_CMD register write - extract data byte
        expected_data_queue.push_back(data_byte);
        `uvm_info("SCOREBOARD", $sformatf("APB WRITE DATA_CMD=0x%02x CMD=%b queue_size=%0d", data_byte, cmd_bit, expected_data_queue.size()), UVM_MEDIUM)
      end
      if (tr.kind == apb_transfer::APB_READ && tr.addr == 8'h0C) begin
        // DATA_CMD register read - compare with received data
        if (received_data_queue.size() > 0) begin
          `uvm_info("SCOREBOARD", $sformatf("APB READ DATA_CMD=0x%02x vs RX_FIFO=0x%02x", tr.data[7:0], rcvd), UVM_MEDIUM)
          if (rcvd !== tr.data[7:0]) begin
            `uvm_error("DATA_MISMATCH", $sformatf("MISMATCH: expected=0x%02x actual=0x%02x", rcvd, tr.data[7:0]))
            mismatch_count++;
          end else begin
            match_count++;
          end
        end
      end
    end
  endtask

  // Process I2C transactions
  task process_i2c_fifo();
            reg [7:0] exp = expected_data_queue.pop_front();
    i2c_transfer tr;
    forever begin
      i2c_fifo.get(tr);
      if (tr.kind == i2c_transfer::I2C_WRITE && tr.data.size() > 0) begin
        foreach (tr.data[i]) begin
          if (expected_data_queue.size() > 0) begin
            if (exp !== tr.data[i]) begin
              `uvm_error("I2C_MISMATCH", $sformatf("I2C_WRITE: expected=0x%02x actual=0x%02x", exp, tr.data[i]))
              mismatch_count++;
            end else begin
              match_count++;
              `uvm_info("SCOREBOARD", $sformatf("I2C_WRITE matched: 0x%02x", exp), UVM_LOW)
            end
          end
        end
      end
      if (tr.kind == i2c_transfer::I2C_READ && tr.data.size() > 0) begin
        foreach (tr.data[i]) begin
          received_data_queue.push_back(tr.data[i]);
          `uvm_info("SCOREBOARD", $sformatf("I2C_READ rcvd: 0x%02x queue_size=%0d", tr.data[i], received_data_queue.size()), UVM_LOW)
        end
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("SCOREBOARD", $sformatf("=== Scoreboard Report ==="), UVM_LOW)
    `uvm_info("SCOREBOARD", $sformatf("Matches:   %0d", match_count), UVM_LOW)
    `uvm_info("SCOREBOARD", $sformatf("Mismatches: %0d", mismatch_count), UVM_LOW)
    if (mismatch_count == 0)
      `uvm_info("SCOREBOARD", "PASS: All data matched!", UVM_LOW)
    else
      `uvm_error("SCOREBOARD_FAIL", $sformatf("FAIL: %0d mismatches found", mismatch_count))
  endfunction

endclass : scoreboard