# VCS 仿真问题记录

## 2026-04-27 UVM 验证环境卡死问题

### 问题现象
- 仿真启动后立即终止（time=0），收到 SIGTERM
- UVM phases 卡在 `start_of_simulation` 阶段
- 输出大量 `SAFE-CONT` 系统消息

### 最初诊断结论
以为是 VCS 2018.09-SP2 与 Ubuntu 24.04 (glibc 2.39) 的运行时兼容性问题。

### 实际根因（3个独立问题叠加）

---

#### Issue #1: 空 always 块导致死循环 🔴 严重

**文件**: `tb/uvm/src/i2c/i2c_if.sv` 第 19 行

**错误代码**:
```systemverilog
// Weak pull-up simulation (when output enable is 0)
always begin
  // Pull-up effect handled in driver/monitor
end
```

**问题**: 空 `always begin ... end` 没有任何时间推进语句，导致综合/仿真工具检测到 Infinite Loop (ILD)。

**现象**: VCS 编译报警告：
```
Warning-[ILD] Infinite Loop Detected
tb/uvm/src/i2c/i2c_if.sv, 19
  The simulator might be hung due to an infinite loop.
```

**修复**: 删除该空 always 块，注释说明已在 driver/monitor 中处理。

---

#### Issue #2: Agent 缺少 Sequencer 导致 NOA 🔴 严重

**文件**: `i2c_master_agent.sv`, `i2c_slave_agent.sv`, `apb_driver.sv`

**问题**: 这三个 `uvm_driver` 子类都没有创建和连接 `uvm_sequencer`，导致 `seq_item_port` 为 null pointer。

**现象**:
```
Error-[NOA] Null object access
\i2c_master_agent::run_phase at i2c_master_agent.sv:134
  seq_item_port.get_next_item(tr);
```

**根本原因**: UVM-1.1 中 `uvm_driver` 默认不创建 sequencer，需要手动在 build_phase 创建并通过 connect_phase 连接。

**修复方法**:

```systemverilog
// 1. 添加 sequencer 成员变量
uvm_sequencer #(i2c_transfer) sequencer;

// 2. build_phase 中创建
sequencer = uvm_sequencer #(i2c_transfer)::type_id::create("sequencer", this);

// 3. connect_phase 中连接
function void connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  seq_item_port.connect(sequencer.seq_item_export);
endfunction
```

---

#### Issue #3: Scoreboard 变量在声明前使用 🟡 中等

**文件**: `tb/uvm/src/env/scoreboard.sv`

**错误代码**:
```systemverilog
task process_apb_fifo();
  reg [7:0] data_byte = tr.data[7:0];  // ← tr 在下面才声明！
  logic cmd_bit = tr.data[8];
  reg [7:0] rcvd = received_data_queue.pop_front();
  apb_transfer tr;                     // ← 声明在这里
  forever begin
    apb_fifo.get(tr);
    ...
```

**问题**: SystemVerilog 允许在 task 级别声明变量，但这些声明的初始化语句会在 forever 循环执行前就被求值，此时 `tr` 尚未定义。

**修复**: 将变量声明移到 forever 循环内部或之后：
```systemverilog
task process_apb_fifo();
  apb_transfer tr;           // 移到前面，不带初始化
  logic [7:0] data_byte;    // 分开声明，不依赖 tr
  logic cmd_bit;
  forever begin
    apb_fifo.get(tr);
    data_byte = tr.data[7:0];  // 在循环内赋值
    cmd_bit   = tr.data[8];
    ...
```

---

#### Issue #4: APB Driver 与 Test 直接驱动冲突 🟡 中等

**文件**: `apb_driver.sv` + test 类

**问题**: APB driver 的 `run_phase` 持续驱动 APB 信号，同时 test 的 `apb_write()`/`apb_read()` 任务也直接驱动同一信号，造成冲突。

**修复策略**: 让 APB driver 保持 idle（只拉低信号），test 直接通过 `env.apb_drv.vif` 访问 APB 接口：

```systemverilog
// apb_driver.sv - run_phase 改为 idle
task run_phase(uvm_phase phase);
  forever begin
    @(posedge vif.pclk);
    vif.psel    <= 1'b0;
    vif.penable <= 1'b0;
    vif.pwrite  <= 1'b0;
    vif.paddr   <= 8'h0;
    vif.pwdata  <= 32'h0;
  end
endtask

// test 中直接驱动
task apb_write(input logic [7:0] addr, input logic [31:0] data);
  virtual apb_if vif = env.apb_drv.vif;
  @(posedge vif.pclk);
  vif.psel    <= 1'b1;
  vif.penable <= 1'b0;
  vif.pwrite  <= 1'b1;
  vif.paddr   <= addr;
  vif.pwdata  <= data;
  @(posedge vif.pclk);
  vif.penable <= 1'b1;
  @(posedge vif.pclk);
  while (!vif.pready) @(posedge vif.pclk);
  vif.psel    <= 1'b0;
  vif.penable <= 1'b0;
endtask
```

---

### 教训总结

1. **空 always 块几乎总是死循环** — 任何 `always begin ... end` 必须包含 `@` 时间控制或 `#` 延时
2. **VCS ILD 警告不能忽视** — 编译器检测到无限循环，仿真必然卡死
3. **sequencer 不是自动创建的** — UVM-1.1 的 `uvm_driver` 需要手动创建和连接 sequencer
4. **变量初始化在声明处求值** — SystemVerilog 中 `logic x = foo()` 会在 task 入口立即执行 `foo()`，而非等到首次使用
5. **driver 和 test 不要同时驱动同一信号** — 明确职责：driver 管理总线 idle 行为，test 控制时序

### 修改的文件
| 文件 | 修改类型 |
|------|----------|
| `tb/uvm/src/i2c/i2c_if.sv` | 删除空 always 块 |
| `tb/uvm/src/i2c/i2c_master_agent.sv` | 添加 sequencer |
| `tb/uvm/src/i2c/i2c_slave_agent.sv` | 添加 sequencer |
| `tb/uvm/src/apb/apb_driver.sv` | 添加 sequencer + idle run_phase |
| `tb/uvm/src/env/scoreboard.sv` | 重写 process_apb_fifo / process_i2c_fifo |
| `tb/uvm/src/tests/basic/test_basic_master_single_write.sv` | 改为直接驱动 APB 信号 |
