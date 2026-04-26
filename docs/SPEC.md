# I2C Controller 设计规格书 v2.0

**文件路径:** `i2c_controller/docs/SPEC.md`
**版本:** v2.0
**日期:** 2026-04-26
**作者:** Jack & 小蜂
**架构参考:** DesignWare DW_apb_i2c

---

## 1. 概述

### 1.1 模块功能

实现一个完整的 **I2C Controller IP**，同时支持 **Master 模式** 和 **Slave 模式**：

- **Master 发射**：CPU/APB 写入 TX FIFO，I2C Master 自动生成完整 I2C transaction（START → 地址 → 数据 → STOP/RepeatedSTART）
- **Master 接收**：配置读命令后，I2C Master 生成 START → 地址，接收数据存入 RX FIFO，CPU/APB 读取
- **Slave 接收**：I2C Slave 响应地址匹配后，接收数据存入 RX FIFO，CPU/APB 读取
- **Slave 发射**：CPU/APB 写入 TX FIFO，Slave 在读事务中自动返回数据

### 1.2 设计范围

| 功能 | 状态 | 说明 |
|------|------|------|
| Master 写（单字节/多字节） | ✅ | TX FIFO 支持连续写 |
| Master 读（单字节/多字节） | ✅ | 支持发出RepeatedSTART |
| Master 目标地址可配 | ✅ | IC_TAR 寄存器 |
| Slave 地址可配 | ✅ | IC_SAR 寄存器 |
| Slave 接收 | ✅ | 地址匹配后自动接收 |
| Slave 发射 | ✅ | 读事务中自动返回 TX FIFO 数据 |
| 中断机制 | ✅ | 多种中断源，可屏蔽 |
| TX/RX FIFO | ✅ | 深度可配（默认 16 级） |
| Standard-mode (100kHz) | ✅ | 可配分频比 |
| Fast-mode (400kHz) | ✅ | 可配分频比 |
| Repeated START | ✅ | Master 自动处理 |
| 时钟拉伸（Clock Stretching） | 暂不 | v2.0 不实现 |
| 10-bit 地址 | 暂不 | v2.0 只支持 7-bit 地址 |
| DMA 接口 | 暂不 | v2.0 不实现 |

### 1.3 应用场景

```
┌──────────────────────────────────────────────────────────────┐
│                    Chip (ASIC/SoC)                          │
│  ┌──────────┐     ┌──────────────────────┐                │
│  │   CPU     │────►│   APB Bus            │                │
│  │ (RISC-V/ │     │        │              │                │
│  │   ARM)   │     │        ▼              │                │
│  └──────────┘     │  ┌───────────────┐    │                │
│                    │  │  I2C Controller│   │                │
│                    │  │               │    │                │
│                    │  │ Master + Slave │   │                │
│                    │  └───────┬───────┘    │                │
│                    └──────────┼────────────┘                │
│                               │                              │
│                    SCL ───────┤                              │
│                    SDA ───────┤                              │
└───────────────────────────────┼──────────────────────────────┘
                                │
                           I2C Bus (external)
                                │
                    ┌───────────┼───────────┐
                    │           │           │
               ┌────┴───┐ ┌────┴───┐ ┌─────┴───┐
               │Sensor  │ │ EEPROM │ │  other │
               │  I2C   │ │  I2C   │ │  I2C   │
               │ Slave  │ │ Slave  │ │ Slave  │
               └────────┘ └────────┘ └─────────┘
```

### 1.4 外部接口

| 端口 | 方向 | 位宽 | 描述 |
|------|------|------|------|
| `pclk` | Input | 1 | APB 时钟（系统时钟） |
| `presetn` | Input | 1 | APB 复位（低有效） |
| `psel` | Input | 1 | APB 选择 |
| `penable` | Input | 1 | APB 使能 |
| `pwrite` | Input | 1 | APB 写信号 |
| `paddr[7:0]` | Input | 8 | APB 地址 |
| `pwdata[31:0]` | Input | 32 | APB 写数据 |
| `prdata[31:0]` | Output | 32 | APB 读数据 |
| `pready` | Output | 1 | APB 准备信号（固定为1） |
| `scl_i` | Input | 1 | I2C SCL 输入 |
| `scl_o` | Output | 1 | I2C SCL 输出（Master 驱动） |
| `scl_oe` | Output | 1 | SCL 输出使能 |
| `sda_i` | Input | 1 | I2C SDA 输入 |
| `sda_o` | Output | 1 | I2C SDA 输出 |
| `sda_oe` | Output | 1 | SDA 输出使能 |
| `intr` | Output | 1 | 中断输出（高有效） |

---

## 2. I2C 协议基础

### 2.1 总线参数

| 参数 | 值 |
|------|-----|
| 地址宽度 | 7-bit |
| 数据宽度 | 8-bit（每字节） |
| 位序 | MSB first（bit7 先发，bit0 后发） |
| 总线空闲 | SCL=1, SDA=1 |
| START 条件 | SCL=1 时，SDA 1→0 |
| STOP 条件 | SCL=1 时，SDA 0→1 |
| Repeated START | 前一个 STOP 之前的新 START |
| ACK | SCL=0 期间，SDA 被接收方拉低 |
| NACK | SCL=0 期间，SDA 保持高（接收方不拉低） |

### 2.2 总线时序

```
           START
            │
    ────────┐         ┌─────────────────────────────────────
 SDA ───────┘         └─────────────/───────────────
            │  7-bit addr  │ R/W │   8-bit data   │
    ──────────┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬──
 SCL ───┐  ┌─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┐  ┌─
    ────┘  └─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┘  └──
             │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
             0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
                ADDR[6:0]    R/W   DATA[7:0]
```

### 2.3 数据有效性

```
规则：
- SCL=1 期间，SDA 必须稳定（数据位 或 START/STOP 标志）
- SDA 切换在 SCL=0 期间完成
- SCL 上升沿采样 SDA（数据建立后采样）
```

### 2.4 ACK/NACK 行为

| 场景 | 发送方 | 接收方动作 |
|------|--------|-----------|
| 地址匹配 | Master | Slave 拉低 SDA |
| 地址不匹配 | Master | Slave 保持高阻，Master 自己可拉低（NACK） |
| 数据接收 OK | Master | Slave 拉低 SDA |
| 数据接收异常 | Master | Slave 保持高阻 |

---

## 3. 寄存器映射

### 3.1 地址分配（APB offset, 0x00~0xFF）

| Offset | 寄存器名 | 缩写 | 描述 |
|--------|---------|------|------|
| 0x00 | I2C_CON | CON | 控制寄存器 |
| 0x04 | I2C_TAR | TAR | Master 目标地址 |
| 0x08 | I2C_SAR | SAR | Slave 地址 |
| 0x0C | I2C_DATA_CMD | DAT | 数据读写（Master 写 TX / 读 RX） |
| 0x10 | I2C_SS_SCL_HCNT | SSHCNT | Standard-mode SCL 高电平计数 |
| 0x14 | I2C_SS_SCL_LCNT | SSLCNT | Standard-mode SCL 低电平计数 |
| 0x18 | I2C_FS_SCL_HCNT | FSHCNT | Fast-mode SCL 高电平计数 |
| 0x1C | I2C_FS_SCL_LCNT | FSLCNT | Fast-mode SCL 低电平计数 |
| 0x20 | I2C_INTR_MASK | IMSK | 中断屏蔽寄存器 |
| 0x24 | I2C_RAW_INTR_STAT | IRIS | 原始中断状态（屏蔽前） |
| 0x28 | I2C_RX_TL | RXTL | RX FIFO 阈值 |
| 0x2C | I2C_TX_TL | TXTL | TX FIFO 阈值 |
| 0x30 | I2C_ENABLE | EN | I2C 使能寄存器 |
| 0x34 | I2C_STATUS | STAT | 状态寄存器（只读） |
| 0x38 | I2C_TXFLR | TXFLR | TX FIFO 深度（只读） |
| 0x3C | I2C_RXFLR | RXFLR | RX FIFO 深度（只读） |
| 0x40 | I2C_SDA_HOLD | SDAHD | SDA 保持时间配置 |
| 0x44 | I2C_TX_ABORT_SOURCE | TXABRT | 传输中止源（只读，清零） |
| 0x48 | I2C_ENABLE_STATUS | ENSTAT | Enable 状态（只读） |

> **说明：** 所有寄存器支持 8-bit / 16-bit / 32-bit 访问（APB 宽度 32-bit，实际数据低 8 位有效）。

---

### 3.2 寄存器详细定义

#### 3.2.1 I2C_CON (0x00) — 控制寄存器

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| 0 | MASTER_MODE | RW | 1 | 1=Master 模式，0=Slave 模式 |
| 1 | SPEED | RW | 2'b11 | 1=标准(100k), 2=快速(400k), 3=快速+(1MHz) |
| 2 | SLave_ADDR_10BIT | RW | 0 | 0=7-bit 地址，1=10-bit 地址（v2.0 固定为0） |
| 3 | MASTER_ADDR_10BIT | RW | 0 | 0=7-bit 地址，1=10-bit 地址（v2.0 固定为0） |
| 4 | RESTART_EN | RW | 1 | 1=允许 Repeated START，0=禁止 |
| 5 | SLAVE_DISABLE | RW | 1 | 1=禁用 Slave 功能（纯 Master 模式） |
| 6 | STOP_DET_IF_MASTER_ACTIVE | RW | 0 | Master active 时检测 STOP |
| 7 | RX_FIFO_FULL_HLD | RW | 0 | RX FIFO 满时时钟拉伸 |
| [31:8] | Reserved | RO | 0 | 保留 |

```
SPEED 编码:
2'b01 = Standard-mode (100kHz)
2'b10 = Fast-mode (400kHz)
2'b11 = Fast-mode+ (1MHz)
```

---

#### 3.2.2 I2C_TAR (0x04) — Master 目标地址

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [9:0] | TAR | RW | 10'h000 | Master 发送的目标 I2C 从机地址（7-bit，bit[6:0]，bit[9:7]=0） |
| 10 | GC_OR_START | RW | 0 | 1=发送 General Call (0x00)，0=正常地址 |
| 11 | SPECIAL | RW | 0 | 1=启用 GC_OR_START，0=普通地址 |
| [31:12] | Reserved | RO | 0 | 保留 |

> **注意：** 地址只使用 bit[6:0]，bit[9:7] 必须为 0。

---

#### 3.2.3 I2C_SAR (0x08) — Slave 地址

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [6:0] | SAR | RW | 7'h00 | Slave 响应地址（7-bit） |
| [31:7] | Reserved | RO | 0 | 保留 |

---

#### 3.2.4 I2C_DATA_CMD (0x0C) — 数据命令寄存器

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [7:0] | DAT | W/RW | 8'h00 | **写：** 待发送数据（Master 发射/ Slave 发射）<br>**读：** 接收数据（Master 接收/ Slave 接收）|
| 8 | CMD | WO | 1'b0 | **Master 读时必须写 1**，写事务时写 0。<br>Slave 模式下写 0 表示发送数据 |
| 9 | STRETCH_CLOCK | WO | 1'b0 | 1=Stretch 时钟直到 TX FIFO 空（Slave 发射时） |
| [31:10] | Reserved | RO | 0 | 保留 |

**写行为（Master 发射）：** 写 DAT 即触发一次 I2C 写事务（START → 地址 → DAT → STOP）

**写行为（Master 接收）：** 写 DAT=任意值 + CMD=1，触发一次 I2C 读事务（START → 地址 → 读 → STOP）

**读行为（任意模式）：** 读 DAT 返回 RX FIFO 中的最新数据

---

#### 3.2.5 I2C_SS_SCL_HCNT (0x10) — Standard-mode SCL 高电平计数

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [15:0] | SSHCNT | RW | 16'd400 | SCL 高电平周期数（pclk cycles）<br>计算：pclk频率 / (2 × I2C频率) - 1<br>例：100MHz pclk → 100kHz I2C: 100000000/(2×100000)-1=499 |
| [31:16] | Reserved | RO | 0 | 保留 |

> **注意：** 实际 SCL 频率 = pclk / (2 × (HCNT+1))

---

#### 3.2.6 I2C_SS_SCL_LCNT (0x14) — Standard-mode SCL 低电平计数

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [15:0] | SSLCNT | RW | 16'd400 | SCL 低电平周期数（pclk cycles） |
| [31:16] | Reserved | RO | 0 | 保留 |

---

#### 3.2.7 I2C_FS_SCL_HCNT (0x18) — Fast-mode SCL 高电平计数

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [15:0] | FSHCNT | RW | 16'd60 | Fast-mode SCL 高电平周期数<br>例：100MHz pclk → 400kHz I2C: 100000000/(2×400000)-1=124 |
| [31:16] | Reserved | RO | 0 | 保留 |

---

#### 3.2.8 I2C_FS_SCL_LCNT (0x1C) — Fast-mode SCL 低电平计数

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [15:0] | FSLCNT | RW | 16'd130 | Fast-mode SCL 低电平周期数 |
| [31:16] | Reserved | RO | 0 | 保留 |

---

#### 3.2.9 I2C_INTR_MASK (0x20) — 中断屏蔽寄存器

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| 0 | M_RX_FULL | RW | 1 | RX FIFO >= RX_TL 时屏蔽 |
| 1 | M_TX_EMPTY | RW | 1 | TX FIFO <= TX_TL 时屏蔽 |
| 2 | M_TX_ABRT | RW | 1 | 传输中止屏蔽 |
| 3 | M_RX_DONE | RW | 1 | Slave 接收完数据（发送了 NACK）屏蔽 |
| 4 | M_RX_OVER | RW | 1 | RX FIFO 溢出屏蔽 |
| 5 | M_TX_OVER | RW | 1 | TX FIFO 溢出屏蔽 |
| 6 | M_RD_REQ | RW | 1 | Slave 被请求发射数据屏蔽 |
| 7 | M_TX_EMPTY_HLT | RW | 1 | TX FIFO 空且不再发射屏蔽 |
| 8 | M_STP_DET | RW | 1 | STOP 检测屏蔽 |
| 9 | M_START_DET | RW | 1 | START 检测屏蔽 |
| 10 | M_ACTIVITY | RW | 0 | 总线活动屏蔽 |
| [31:11] | Reserved | RO | 0 | 保留 |

> **只读状态的读取：** RAW_INTR_STAT (0x24) 读取屏蔽前原始中断状态；INTR_STAT (0x24) 读取屏蔽后最终状态。

---

#### 3.2.10 I2C_RAW_INTR_STAT (0x24) — 原始中断状态

| Bit | 名称 | 描述 |
|-----|------|------|
| 0 | R_RX_FULL | RX FIFO >= RX_TL |
| 1 | R_TX_EMPTY | TX FIFO <= TX_TL |
| 2 | R_TX_ABRT | 传输中止（abort） |
| 3 | R_RX_DONE | Slave 接收到 NACK（读事务结束） |
| 4 | R_RX_OVER | RX FIFO 溢出 |
| 5 | R_TX_OVER | TX FIFO 溢出 |
| 6 | R_RD_REQ | Master 请求读 Slave |
| 7 | R_TX_EMPTY_HLT | TX FIFO 空且停止发射 |
| 8 | R_STP_DET | STOP 条件检测 |
| 9 | R_START_DET | START 条件检测 |
| 10 | R_ACTIVITY | I2C 总线活动 |

> 写 1 清零（WC1R），写 0 无效。

---

#### 3.2.11 I2C_RX_TL (0x28) — RX FIFO 阈值

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [4:0] | RX_TL | RW | 5'd0 | RX FIFO 触发中断的阈值<br>RX FIFO count >= RX_TL 时 R_RX_FULL=1 |
| [31:5] | Reserved | RO | 0 | 保留 |

---

#### 3.2.12 I2C_TX_TL (0x2C) — TX FIFO 阈值

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [4:0] | TX_TL | RW | 5'd0 | TX FIFO 触发中断的阈值<br>TX FIFO count <= TX_TL 时 R_TX_EMPTY=1 |
| [31:5] | Reserved | RO | 0 | 保留 |

---

#### 3.2.13 I2C_ENABLE (0x30) — 使能寄存器

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| 0 | ENABLE | RW | 0 | 1=I2C Controller 使能，0=禁用 |
| 1 | ABORT | RW | 0 | 1=中止当前传输，传输完成后自动清零 |
| [31:2] | Reserved | RO | 0 | 保留 |

---

#### 3.2.14 I2C_STATUS (0x34) — 状态寄存器（只读）

| Bit | 名称 | 描述 |
|-----|------|------|
| 0 | ACTIVITY | I2C 总线忙（1=忙） |
| 1 | TFNF | TX FIFO 未满（1=可写） |
| 2 | TFE | TX FIFO 空（1=空） |
| 3 | RFNE | RX FIFO 非空（1=有数据） |
| 4 | RFF | RX FIFO 满（1=满） |
| 5 | MST_ACTIVITY | Master 正在传输（1=活动） |
| 6 | SLV_ACTIVITY | Slave 正在传输（1=活动） |

---

#### 3.2.15 I2C_TXFLR (0x38) — TX FIFO 深度（只读）

| Bit | 名称 | 描述 |
|-----|------|------|------|
| [4:0] | TXFLR | TX FIFO 中当前数据个数 |

---

#### 3.2.16 I2C_RXFLR (0x3C) — RX FIFO 深度（只读）

| Bit | 名称 | 描述 |
|-----|------|------|------|
| [4:0] | RXFLR | RX FIFO 中当前数据个数 |

---

#### 3.2.17 I2C_SDA_HOLD (0x40) — SDA 保持时间

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [15:0] | SDA_HOLD | RW | 16'd1 | SCL 下降沿后 SDA 保持周期数 |
| [31:16] | Reserved | RO | 0 | 保留 |

---

#### 3.2.18 I2C_TX_ABRT_SOURCE (0x44) — 传输中止源（只读，清零）

| Bit | 名称 | 描述 |
|-----|------|------|------|
| 0 | ABRT_7B_NOACK | 地址无响应（7-bit 模式） |
| 1 | ABRT_10ADDR1_NOACK | 10-bit 地址第一个字节无响应 |
| 2 | ABRT_10ADDR2_NOACK | 10-bit 地址第二个字节无响应 |
| 3 | ABRT_TXDATA_NOACK | 数据字节无响应（NACK） |
| 4 | ABRT_GCALL_NOACK | General Call 无响应 |
| 5 | ABRT_GCALL_READ | General Call 后 Master 尝试读 |
| 6 | ABRT_HS_ACKDET | HS Master 无响应 |
| 7 | ABRT_SBYTE_ACKDET | START byte 无响应 |
| 8 | ABRT_HS_NORSTRT | HS 模式 Repeated START 禁用 |
| 9 | ABRT_SBYTE_NORSTRT | START byte 时 Repeated START 禁用 |
| 10 | ABRT_10_NORSTRT | 10-bit 模式 Repeated START 禁用 |
| 11 | ABRT_MASTER_DIS | Master 禁用时尝试传输 |
| 12 | ABRT_ARB_LOST | 仲裁失败（bus arbitration lost） |
| 13 | ABRT_SLVFLUSH_TXFIFO | Slave 清空 TX FIFO |
| 14 | ABRT_SLV_ARBLOST | Slave 仲裁失败 |
| 15 | ABRT_SLVRD_INTXFR | Slave 读冲突 |
| [31:16] | Reserved | RO | 0 |

> **清零：** 读取此寄存器后自动清零（RO,clr on read）。

---

#### 3.2.19 I2C_ENABLE_STATUS (0x48) — Enable 状态（只读）

| Bit | 名称 | 描述 |
|-----|------|------|------|
| 0 | IC_EN | Controller 使能状态（反映 ENABLE.EN） |
| 1 | SLV_ACTIVITY_DISABLED | Slave 活动但被禁用 |
| 2 | MST_ACTIVITY_DISABLED | Master 活动但被禁用 |

---

## 4. 功能描述

### 4.1 整体架构

```
┌──────────────────────────────────────────────────────────────────────┐
│                        I2C Controller 顶层                            │
│                                                                      │
│  APB Interface              Protocol Engine              I/O Buffer  │
│  ┌──────────┐              ┌────────────────┐          ┌───────────┐  │
│  │          │              │                │          │           │  │
│  │  Register│◄────────────►│   FSM Core     │◄────────►│ SCL Gen   │  │
│  │   File   │              │  (Master +     │          │ (Master)  │  │
│  │          │              │   Slave)        │          │           │  │
│  │  + FIFO  │              │                │          └─────┬─────┘  │
│  │          │              │                │                │        │
│  │          │              └────────────────┘          SCL ──┤        │
│  └────┬─────┘                                             │        │
│       │                                                   │        │
│       │ APB                                                     │
│  prdata[31:0]  pwdata[31:0]                            ┌─────┴─────┐  │
│  paddr[7:0]    pwrite                                 │           │  │
│  psel,penable presetn                                 │  SDA I/O  │  │
│                                                     ┌──►           │  │
│                                                     │  └─────┬─────┘  │
│                                                     │        │        │
└─────────────────────────────────────────────────────┼────────┼────────┘
                                                      │        │
                                              sda_i ◄─┘    sda_o,sda_oe
                                              scl_i ◄─┘    scl_o,scl_oe
```

### 4.2 子模块功能划分

| 子模块 | 职责 |
|--------|------|
| **APB Interface** | 寄存器读写译码、FIFO 读/写访问、中断状态管理 |
| **TX FIFO** | 缓存待发送数据，深度 16，提供 full/empty/level 状态 |
| **RX FIFO** | 缓存已接收数据，深度 16，提供 full/empty/level 状态 |
| **Master FSM** | 生成 I2C 总线时序（START/ADDR/DATA/ACK/STOP）、仲裁、时钟生成 |
| **Slave FSM** | 地址匹配、接收/发送数据、时钟拉伸响应 |
| **Clock Generator** | 基于 HCNT/LCNT 产生 SCL 时钟（Master 模式） |
| **SDA/SCL I/O Buffer** | 双向 I/O，OE 控制三态，支持上拉电阻（外置） |

### 4.3 Master 写事务（单字节）

```
CPU 操作顺序：
1. 配置 I2C_TAR = 目标地址（7-bit，bit[6:0]）
2. 配置 I2C_CON.MASTER_MODE = 1, SPEED, RESTART_EN
3. 配置 I2C_ENABLE.EN = 1
4. 写 I2C_DATA_CMD.DAT = 待发送数据（CMD=0）
5. 轮询 I2C_STATUS.TFE 或等待 TX_EMPTY 中断
6. 传输完成后（TX_ABRT 无异常）读 TX_ABRT_SOURCE 确认无错误

I2C 总线结果：
  S  [ADDR+W] A [DATA] A  P
  └─START─┘└─地址+写─┘└─数┘└─ACK┘└─STOP─┘
```

### 4.4 Master 连续写事务（多字节）

```
CPU 操作顺序：
1. 配置 I2C_TAR = 目标地址
2. 配置 I2C_ENABLE.EN = 1
3. 连续写入 I2C_DATA_CMD（最多填满 TX FIFO=16字节）
4. Controller 自动连续发送，直到 TX FIFO 空
5. 轮询 I2C_RAW_INTR_STAT.R_TX_EMPTY 或 R_TX_ABRT

I2C 总线结果（3字节示例）：
  S [ADDR+W] A [DATA0] A [DATA1] A [DATA2] A  P
```

### 4.5 Master 读事务（单字节）

```
CPU 操作顺序：
1. 配置 I2C_TAR = 目标地址
2. 配置 I2C_ENABLE.EN = 1
3. 写 I2C_DATA_CMD = {8'h00, CMD=1}（触发读）
4. 轮询 I2C_RAW_INTR_STAT.R_RX_FULL 或等待 RX_FULL 中断
5. 读 I2C_DATA_CMD 获取 RX FIFO 中的数据

I2C 总线结果：
  S [ADDR+R] A [DATA] NA  P
            └─Master读 ──┘└NACK└─STOP─┘
              DATA 返回
```

### 4.6 Master 连续读事务（多字节）

```
CPU 操作顺序：
1. 配置 I2C_TAR = 目标地址
2. 配置 I2C_ENABLE.EN = 1
3. 连续写 I2C_DATA_CMD 多次（CMD=1），数量=期望读字节数
4. Controller 自动执行读事务直到所有 CMD 处理完
5. 从 RX FIFO 依次读取数据

I2C 总线结果（3字节示例）：
  S [ADDR+R] A [DATA0] A [DATA1] A [DATA2] NA  P
```

### 4.7 Master Repeated START 读（写后读）

```
场景：先写寄存器地址，再 Repeated START 读数据

CPU 操作顺序：
1. 配置 I2C_TAR = 目标地址
2. 配置 I2C_ENABLE.EN = 1
3. 配置 I2C_CON.RESTART_EN = 1
4. 写 I2C_DATA_CMD = {reg_addr, CMD=0}（写寄存器地址）
5. 写 I2C_DATA_CMD = {8'h00, CMD=1}（触发读）
6. 从 RX FIFO 读数据

I2C 总线结果：
  S [ADDR+W] A [REG] A  [ADDR+R] A [DATA] NA  P
                  └─写─┘└─RepeatedSTART─┘└─读─┘
```

### 4.8 Slave 接收事务

```
配置：
1. 配置 I2C_SAR = 本机地址（7-bit）
2. 配置 I2C_CON.MASTER_MODE=0, SLAVE_DISABLE=0
3. 配置 I2C_ENABLE.EN = 1

I2C 总线行为：
- 监听总线，匹配地址后进入 Slave 接收模式
- 自动在 ACK 时隙拉低 SDA
- 接收数据存入 RX FIFO

CPU 操作：
1. 等待/轮询 I2C_RAW_INTR_STAT.R_RX_FULL
2. 读 I2C_DATA_CMD（RX FIFO 深度内可连续读）
3. 处理数据

I2C 总线结果（接收 2 字节）：
  S [ADDR+W] A [DATA0] A [DATA1] A  P
```

### 4.9 Slave 发射事务

```
配置：
1. 配置 I2C_SAR = 本机地址（7-bit）
2. 预先写入 TX FIFO（至少 1 字节）
3. 配置 I2C_ENABLE.EN = 1

I2C 总线行为：
- 匹配地址 + R/W=1，进入 Slave 发射模式
- 从 TX FIFO 取数据驱动 SDA
- Master 发送 ACK/NACK

CPU 操作：
1. 等待/轮询 I2C_RAW_INTR_STAT.R_RD_REQ（Master 请求读）
2. 写 TX FIFO（必须快于 Master 的 SCL 时钟）
3. 等待 R_RX_DONE（Master 发送 NACK 表示结束）

I2C 总线结果（Slave 返回 2 字节）：
  S [ADDR+R] A [DATA0] A [DATA1] NA  P
              └─Slave 发射─┘└NACK└STOP─┘
```

### 4.10 TX_ABRT 中止条件

| 中止原因 | 说明 |
|---------|------|
| ABRT_7B_NOACK | 目标地址无 ACK |
| ABRT_TXDATA_NOACK | 数据字节无 ACK |
| ABRT_ARB_LOST | 仲裁失败（总线上多个 Master 冲突） |
| ABRT_MASTER_DIS | ENABLE=0 时 Master 尝试传输 |
| ABRT_SLVRD_INTXFR | Slave 收到读请求但 TX FIFO 空 |

> **TX_ABRT 清零：** 读取 I2C_TX_ABRT_SOURCE 后自动清零。

---

## 5. FIFO 设计

### 5.1 TX FIFO

| 参数 | 值 |
|------|-----|
| 深度 | 16 级（可配置） |
| 宽度 | 9-bit（8-bit 数据 + 1-bit CMD） |
| 复位 | presetn 异步清零 |
| 满标志 | TXFLR == 5'd16 |
| 空标志 | TXFLR == 5'd0 |

### 5.2 RX FIFO

| 参数 | 值 |
|------|-----|
| 深度 | 16 级（可配置） |
| 宽度 | 8-bit（数据） |
| 复位 | presetn 异步清零 |
| 满标志 | RXFLR == 5'd16 |
| 空标志 | RXFLR == 5'd0 |

### 5.3 FIFO 指针管理

- 读指针/写指针用 gray code 或 binary code 实现
- 空满判断使用 modular arithmetic
- **上溢（Overflow）**：写 FIFO 时 FULL=1 则丢弃，数据不写入
- **下溢（Underflow）**：读 FIFO 时 EMPTY=1 则返回 0x00

---

## 6. 中断架构

### 6.1 中断信号

```
intr = (RAW_INTR_STAT[0]  & ~IMS[0])  |
       (RAW_INTR_STAT[1]  & ~IMS[1])  |
       (RAW_INTR_STAT[2]  & ~IMS[2])  |
       (RAW_INTR_STAT[3]  & ~IMS[3])  |
       (RAW_INTR_STAT[4]  & ~IMS[4])  |
       (RAW_INTR_STAT[5]  & ~IMS[5])  |
       (RAW_INTR_STAT[6]  & ~IMS[6])  |
       (RAW_INTR_STAT[7]  & ~IMS[7])  |
       (RAW_INTR_STAT[8]  & ~IMS[8])  |
       (RAW_INTR_STAT[9]  & ~IMS[9])  |
       (RAW_INTR_STAT[10] & ~IMS[10]);
```

### 6.2 中断处理流程

```
1. CPU 检测 intr == 1
2. 读 I2C_RAW_INTR_STAT，确定哪些中断源触发
3. 读对应状态寄存器（如 RXFLR）获取具体数据
4. 处理数据
5. 写 1 到对应位清除中断（部分中断自动清零）
```

### 6.3 关键中断使用场景

| 中断 | 典型使用 |
|------|---------|
| RX_FULL | RX FIFO 有数据，CPU 读取 |
| TX_EMPTY | TX FIFO 空，CPU 填充新数据 |
| TX_ABRT | 传输失败，CPU 读取 TX_ABRT_SOURCE 分析原因 |
| RX_DONE | Slave 读事务结束，Master 发送了 NACK |
| RD_REQ | Master 请求读 Slave，CPU 准备 TX FIFO 数据 |
| STOP_DET | 检测到 STOP，事务结束 |
| START_DET | 检测到 START，开始事务 |
| ACTIVITY | 总线状态监控 |

---

## 7. 时钟分频配置

### 7.1 pclk 与 I2C 频率关系

```
I2C SCL 周期 = (HCNT + 1) + (LCNT + 1) 个 pclk 周期
I2C 频率 = pclk / ((HCNT + 1) + (LCNT + 1))

通常设置 HCNT ≈ LCNT，偶数分频效果更好。

SCL 高电平时间 = (HCNT + 1) / pclk
SCL 低电平时间 = (LCNT + 1) / pclk
```

### 7.2 常用配置（pclk = 100MHz）

| I2C 模式 | 目标频率 | HCNT | LCNT | 计算 |
|---------|---------|------|------|------|
| Standard 100kHz | 100 kHz | 499 | 499 | 100M/200k-1=499 |
| Fast 400kHz | 400 kHz | 124 | 130 | 100M/800k ≈124 |

> **实测调整：** 不同 I2C 从机对上沿/下沿有要求，实际 HCNT/LCNT 可能需要微调。

---

## 8. 总线接口时序

### 8.1 APB 访问时序

```
pclk
psel      ───┐    ┌──────────────────────
penable        └──┐    ┌───────────────
paddr              └────┐    ┌────────
pwdata              └────┴────┘
pwrite              └────────────
pready      ──────────────────────────────────
prdata      ──────────────────────────────────

写时序（pready=1）：
- psel=1, pwrite=1, penable=1 时写入
- presetn 期间 pready 始终为 1

读时序（pready=1）：
- psel=1, pwrite=0, penable=1 时读取
- prdata 在 penable 上升沿后稳定
```

### 8.2 I2C 输出驱动时序

```
scl_oe=1 时（Master 驱动 SCL）：
- SCL 由内部时钟分频生成
- scl_o 驱动 SCL

sda_oe=1 时（任意模式驱动 SDA）：
- sda_o 被驱动到总线
- 总线实际电平 = 上拉电阻 + sda_oe 拉低

sda_oe=0 时：
- SDA 高阻，由上拉电阻拉高
- 可采样 sda_i 读取总线电平
```

---

## 9. 复位行为

| 复位信号 | 影响 |
|---------|------|
| presetn=0 | 所有 APB 寄存器清零，TX/RX FIFO 清空，状态机回 IDLE |
| presetn=1 且 ENABLE=1 | Controller 正常工作 |
| ENABLE=0 | Controller 停止，SCL/SDA 释放（高阻），寄存器保持 |

> **Soft Reset：** 设置 ENABLE=0 等待 MST_ACTIVITY=0 后重新配置，等效于软复位。

---

## 10. 状态机定义

### 10.1 Master FSM

```
状态列表：
IDLE          — 空闲，等待 TX_CMD
M_START       — 发送 START + 地址字节
M_ADDR        — 发送地址字节（包含 R/W bit）
M_WDATA       — 发送数据字节
M_RDATA       — 接收数据字节（Master 主动提供时钟）
M_ACK         — 发送 ACK/NACK
M_STOP        — 发送 STOP
M_IDLE_WAIT   — 等待 TX FIFO 空后进入 IDLE
```

### 10.2 Master 状态转移图

```
                        TX_FIFO 有待发数据
                   ┌──────────────────────────────┐
                   │                              ▼
               IDLE ─────────────────────────► M_START
                   ▲                              │
                   │                              │ SCL 高电平
                   │                              ▼
                   │                         M_ADDR
                   │                              │
                   │              ┌────────────────┤
                   │              │                │
                   │         R/W=0            R/W=1
                   │              │                │
                   │              ▼                ▼
                   │         M_WDATA ──────► M_RDATA
                   │              │                │
                   │              │ SCL↓×8         │ SCL↓×8
                   │              │                │
                   │              ▼                ▼
                   │         M_ACK ◄───────── M_ACK
                   │              │                │
                   │              │  ACK?           │ NACK?
                   │              ▼                │
                   │     TX_FIFO空?                │
                   │        │                      │
                   │   no   │  yes                 │
                   │        ▼                      │
                   │   M_WDATA (next)             │
                   │        │                      │
                   │        │ TX_FIFO空            │
                   │        ▼                      │
                   │   M_STOP ────────────────────┤
                   │     │                         │
                   │     │ done                    │
                   │     ▼                         │
                   └────IDLE◄───────────────────────┘
```

### 10.3 Slave FSM

```
状态列表：
S_IDLE        — 空闲，等待地址匹配
S_ADDR        — 接收地址字节
S_ADDR_ACK    — 发送 ACK
S_WDATA       — 接收数据字节
S_WACK        — 发送 ACK
S_RDATA       — 发射数据字节
S_RACK        — 接收 Master ACK/NACK
S_STRETCH     — 时钟拉伸（v2.0 暂不实现）
```

---

## 11. 验证计划

### 11.1 验证架构

```
┌─────────────────────────────────────────────────────────────┐
│                    UVM 验证环境                              │
│                                                             │
│  ┌───────────┐   ┌───────────┐   ┌───────────────┐         │
│  │ APB BFM   │   │ I2C BFM   │   │ Scoreboard    │         │
│  │(驱动寄存器)│   │(模拟I2C   │   │(对比预期数据) │         │
│  │           │   │  Master/  │   │               │         │
│  │           │   │   Slave)  │   │               │         │
│  └─────┬─────┘   └─────┬─────┘   └───────┬───────┘         │
│        │                │                 │                │
│        │   ┌────────────┴────────────┐     │                │
│        └──►│       DUT (i2c_ctrl)    │◄────┘                │
│             └────────────┬────────────┘                      │
└──────────────────────────┼───────────────────────────────────┘
                           │  I2C Bus (virtual)
```

### 11.2 功能覆盖点

#### Master 写覆盖率
| 覆盖点 | 说明 |
|--------|------|
| 单字节写 | 目标地址 + 1 字节数据 |
| 多字节写（2~16） | 填满/不填满 TX FIFO |
| 多字节写后 STOP | TX FIFO 空后自动 STOP |
| 多字节写后 Repeated START | 最后一字节后接新 START |
| 地址 NACK | 目标无响应，TX_ABRT 检测 |
| 数据 NACK | 从机无响应数据，TX_ABRT 检测 |
| 仲裁失败 | 多主冲突，TX_ABRT.ABRT_ARB_LOST |

#### Master 读覆盖率
| 覆盖点 | 说明 |
|--------|------|
| 单字节读 | 1 CMD 触发读 |
| 多字节读（2~16） | 连续读 |
| 读后 NACK 最后字节 | Master 最后字节发 NACK |
| 写后读（Repeated START） | 写地址 + Repeated START + 读 |

#### Slave 接收覆盖率
| 覆盖点 | 说明 |
|--------|------|
| 单字节接收 | 匹配地址后接收 1 字节 |
| 多字节接收（2~16） | 连续接收 |
| 地址不匹配 | 不响应，保持沉默 |
| STOP 后重启 | 接收完毕 STOP |

#### Slave 发射覆盖率
| 覆盖点 | 说明 |
|--------|------|
| 单字节发射 | 匹配地址 + R 后返回 1 字节 |
| 多字节发射（2~16） | TX FIFO 预填充 |
| TX FIFO 空时读请求 | RD_REQ 但无数据，ABRT_SLVRD_INTXFR |
| NACK 结束 | Master NACK 后 RX_DONE |

#### 总线事件覆盖率
| 覆盖点 | 说明 |
|--------|------|
| START_DET 中断 | 检测到 START |
| STOP_DET 中断 | 检测到 STOP |
| Repeated START | 写后读，写后写 |
| 时序参数 | 100kHz / 400kHz 不同频率 |

### 11.3 定向测试用例

| # | 测试名称 | 描述 |
|---|---------|------|
| TC01 | master_single_write | 单字节写，地址 0x3C，数据 0xAA |
| TC02 | master_burst_write | 连续写 8 字节 |
| TC03 | master_single_read | 单字节读 |
| TC04 | master_burst_read | 连续读 8 字节 |
| TC05 | master_write_then_read | 写寄存器地址后 Repeated START 读 |
| TC06 | master_addr_nack | 目标地址无响应，检测 TX_ABRT |
| TC07 | master_arb_lost | 多主冲突，检测 ABRT_ARB_LOST |
| TC08 | slave_single_receive | I2C BFM 作为 Master 写 Slave |
| TC09 | slave_single_transmit | I2C BFM 作为 Master 读 Slave |
| TC10 | slave_addr_no_match | 错误地址，Slave 不响应 |
| TC11 | speed_100k | Standard-mode 验证 |
| TC12 | speed_400k | Fast-mode 验证 |
| TC13 | interrupt_rx_full | RX FIFO 满中断触发 |
| TC14 | interrupt_tx_empty | TX FIFO 空中断触发 |
| TC15 | interrupt_tx_abrt | TX 中断源验证 |
| TC16 | tx_abort_clear | TX_ABRT 读取后清零 |
| TC17 | fifo_overflow | TX/RX FIFO 溢出 |
| TC18 | fifo_underflow | 空时读 FIFO |
| TC19 | enable_disable | ENABLE 动态切换 |
| TC20 | reset_behavior | presetn 复位验证 |

### 11.4 通过标准

- TC01 ~ TC20 全部通过
- 功能覆盖率 ≥ 95%（各覆盖点至少命中 1 次）
- 状态机覆盖率：所有状态和转移均被覆盖
- 无时序违例（setup/hold）

---

## 12. 设计约束

### 12.1 工艺与工具

| 项目 | 选择 |
|------|------|
| 设计语言 | SystemVerilog (IEEE 1800) |
| 仿真工具 | Synopsys VCS 2018.09+ |
| 综合工具 | Synopsys Design Compiler 2018.06+ |
| 目标工艺 | 自定义（无特定工艺约束） |
| 代码风格 | 可综合 RTL，无 unsafe 语法 |

### 12.2 综合要求

- 时序路径：APB 寄存器访问 < 1 pclk cycle
- I2C 时钟域：SCL 由内部分频产生，与 pclk 同源
- 跨时钟域：I2C 总线信号（scl_i/sda_i）通过 2 级同步器接入
- 面积目标：小于 10K ASIC gates（含 FIFO）

### 12.3 代码规范

```
always_ff @(posedge pclk or negedge presetn)  // FF 使用
always_comb                                     // 组合逻辑

不允许：
- always @* 混用（统一用 always_ff / always_comb）
- #delay 延时语句
- force/release
- 内置 $display 用于设计代码（TB 除外）
```

---

## 13. 未来扩展

- [ ] 时钟拉伸（Clock Stretching）
- [ ] 10-bit 地址支持
- [ ] General Call 地址支持
- [ ] SMBus 协议兼容
- [ ] DMA 接口
- [ ] HS-mode (3.4MHz)
- [ ] 多主机仲裁

---

## 14. 修订历史

| 版本 | 日期 | 修改内容 |
|------|------|---------|
| v2.0 | 2026-04-26 | 全新规格，参考 DW_apb_i2c 架构，覆盖 Master+Slave 完整功能，Jack & 小蜂 |
