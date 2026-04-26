# I2C Controller 设计规格书 v2.2

**文件路径:** `i2c_controller/docs/SPEC.md`
**版本:** v2.2
**日期:** 2026-04-26
**作者:** Jack & 小蜂
**架构参考:** DesignWare DW_apb_i2c
**协议参考:** NXP UM10204 I2C-bus specification and user manual (Rev.7, 2021)

> **v2.2 主要更新（2026-04-26）：** Q4~Q14 需求确认修正：INTR_STAT/RAW_INTR_STAT 地址拆分（0x24/0x28）、SPEED 字段改为 CON[2:1]、MODE 双配置表、STOP_DET_IF_MASTER_ACTIVE 含义澄清、删除 M_IDLE_WAIT 状态、FIFO 深度参数化、精确地址匹配规则、未定义地址 prdata=0、地址表整体前移4字节。
**UM10204 下载:** https://www.nxp.com/docs/en/user-guide/UM10204.pdf

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

| 场景 | SDA 驱动方 | 动作 |
|------|-----------|------|
| 地址匹配，Slave 响应 | **Slave** | SCL=0 期间 Slave 拉低 SDA |
| 地址不匹配，Slave 不响应 | **Slave** | 保持高阻（不驱动 SDA） |
| 数据字节接收正常（Master→Slave） | **Slave** | SCL=0 期间 Slave 拉低 SDA |
| 数据字节接收正常（Slave→Master） | **Master** | SCL=0 期间 Master 拉低 SDA |
| NACK（Master 读最后字节） | **Master** | SCL=0 期间 Master 驱动 SDA=1（不拉低） |
| NACK（Slave 收到无效数据） | **Slave** | 保持高阻 |

> **NACK 的本质：** NACK 不是"没有 ACK"，而是接收方**主动驱动 SDA=1**（高电平）表示"我不想再接收了"。I2C 总线上没有"被动高电平"——SDA 被上拉电阻拉高，但上拉本身不等于 NACK。

---

### 2.5 NXP UM10204 时序参数（官方 I2C 总线标准）

> **参考文档：** NXP UM10204 — I2C-bus specification and user manual（I2C-bus Specification UM10204, Rev. 7, October 2021）
> **下载地址：** https://www.nxp.com/docs/en/user-guide/UM10204.pdf

#### 2.5.1 Standard-mode (100kHz) 时序参数

| 符号 | 参数 | 最小值 | 最大值 | 单位 | 说明 |
|------|------|--------|--------|------|------|
| f_SCL | SCL 时钟频率 | — | 100 | kHz | |
| t_LOW | SCL 低电平时间 | 4.7 | — | μs | Master 驱动 |
| t_HIGH | SCL 高电平时间 | 4.0 | — | μs | Master 驱动 |
| t_SU_STA | START 建立时间 | 4.7 | — | μs | SDA 下降前 SCL 高电平时间 |
| t_HD_STA | START 保持时间 | 4.0 | — | μs | SCL 下降沿后 SDA 保持低的时间 |
| t_SU_DAT | 数据建立时间 | 250 | — | ns | SCL 上升沿前 SDA 稳定时间 |
| t_HD_DAT | 数据保持时间 | 0 | 3.45 | μs | SCL 下降沿后 SDA 保持时间 |
| t_SU_STO | STOP 建立时间 | 4.0 | — | μs | SCL 高电平期间 SDA 上升沿 |
| t_BUF | 总线空闲时间 | 4.7 | — | μs | STOP 到下一个 START 之间 |
| t_r | SDA/SCL 上升沿时间 | — | 1000 | ns | 总线上 RC 常数决定 |
| t_f | SDA/SCL 下降沿时间 | — | 300 | ns | 总线电容 < 200pF 时 |

#### 2.5.2 Fast-mode (400kHz) 时序参数

| 符号 | 参数 | 最小值 | 最大值 | 单位 | 说明 |
|------|------|--------|--------|------|------|
| f_SCL | SCL 时钟频率 | — | 400 | kHz | |
| t_LOW | SCL 低电平时间 | 1.3 | — | μs | |
| t_HIGH | SCL 高电平时间 | 0.6 | — | μs | |
| t_SU_STA | START 建立时间 | 0.6 | — | μs | |
| t_HD_STA | START 保持时间 | 0.6 | — | μs | |
| t_SU_DAT | 数据建立时间 | 100 | — | ns | |
| t_HD_DAT | 数据保持时间 | 0 | 0.9 | μs | |
| t_SU_STO | STOP 建立时间 | 0.6 | — | μs | |
| t_BUF | 总线空闲时间 | 1.3 | — | μs | |
| t_r | SDA/SCL 上升沿时间 | 20 | 300 | ns | |
| t_f | SDA/SCL 下降沿时间 | — | 300 | ns | |

#### 2.5.3 Fast-mode Plus (1MHz) 时序参数

| 符号 | 参数 | 最小值 | 最大值 | 单位 | 说明 |
|------|------|--------|--------|------|------|
| f_SCL | SCL 时钟频率 | — | 1000 | kHz | |
| t_LOW | SCL 低电平时间 | 0.5 | — | μs | |
| t_HIGH | SCL 高电平时间 | 0.26 | — | μs | |
| t_SU_STA | START 建立时间 | 0.26 | — | μs | |
| t_HD_STA | START 保持时间 | 0.26 | — | μs | |
| t_SU_DAT | 数据建立时间 | 50 | — | ns | |
| t_HD_DAT | 数据保持时间 | 0 | 0.7 | μs | |
| t_SU_STO | STOP 建立时间 | 0.26 | — | μs | |
| t_BUF | 总线空闲时间 | 0.5 | — | μs | |

#### 2.5.4 时序图（START / 数据 / STOP）

```
         START condition
            │
    SDA ───┐  ┌───────────────────────/──────────────
            └──┘                              SDA: 1→0 while SCL=1
                  7-bit address │R/W│   8-bit data    │
    SCL ───┐  ┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─
            └──┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
                 │                             │
                 0   1   2   3   4   5   6   7   0   1 ...
                 ADDR[6:0]    R/W   DATA[7:0]

         ACK bit after each byte:
              SCL ──┐  ┌────────────────────────
                    └──┘
                    SDA pulled LOW by receiver during ACK

         STOP condition:
                          SDA ────────┐  ┌─────
                                      └──┘     SDA: 0→1 while SCL=1
                    SCL ────────────────────┘
```

#### 2.5.5 SDA 数据采样点说明

```
SCL ─────────────┬─────────────────────┬─────────────────────
                  │ rising edge         │
                  │ (sample point)      │
              ───┴─────────────────────┴───────────────────────
SDA: ─────────────────[bit changes]──────────────
                  │← t_SU_DAT →│← t_HD_DAT →│
                  数据建立      数据保持
```

**RTL 设计要点：**
- **采样时刻：** SCL 上升沿前 t_SU_DAT 时间内 SDA 必须稳定
- **数据变化窗口：** SCL 高电平期间 SDA 严禁变化（START/STOP 除外）
- **设计实现：** 本 Controller 以 pclk 为参考，HCNT/LCNT 决定 SCL 频率，实际 t_SU_DAT / t_HD_DAT 取决于 pclk 分频比和 SDA 同步器延迟

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
| 0x24 | I2C_INTR_STAT | IST | 中断状态（屏蔽后，只读） |
| 0x28 | I2C_RAW_INTR_STAT | IRIS | 原始中断状态（屏蔽前，只读） |
| 0x2C | I2C_RX_TL | RXTL | RX FIFO 阈值 |
| 0x30 | I2C_TX_TL | TXTL | TX FIFO 阈值 |
| 0x34 | I2C_ENABLE | EN | I2C 使能寄存器 |
| 0x38 | I2C_STATUS | STAT | 状态寄存器（只读） |
| 0x3C | I2C_TXFLR | TXFLR | TX FIFO 深度（只读） |
| 0x40 | I2C_RXFLR | RXFLR | RX FIFO 深度（只读） |
| 0x44 | I2C_SDA_HOLD | SDAHD | SDA 保持时间配置 |
| 0x48 | I2C_TX_ABORT_SOURCE | TXABRT | 传输中止源（只读，清零） |
| 0x4C | I2C_ENABLE_STATUS | ENSTAT | Enable 状态（只读） |

> **地址 0x00~0x4C 共 20 个寄存器。未定义地址（0x50~0xFF）读取返回 32'h0。**

> **说明：** 所有寄存器支持 8-bit / 16-bit / 32-bit 访问（APB 宽度 32-bit，实际数据低 8 位有效）。

---

### 3.2 寄存器详细定义

#### 3.2.1 I2C_CON (0x00) — 控制寄存器

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| 0 | MASTER_MODE | RW | 1 | 1=Master 模式，0=Slave 模式 |
| [2:1] | SPEED | RW | 2'b11 | 2'b01=标准(100k), 2'b10=快速(400k), 2'b11=快速+(1MHz) |
| 3 | SLave_ADDR_10BIT | RW | 0 | 0=7-bit 地址，1=10-bit 地址（v2.0 固定为0） |
| 4 | MASTER_ADDR_10BIT | RW | 0 | 0=7-bit 地址，1=10-bit 地址（v2.0 固定为0） |
| 5 | RESTART_EN | RW | 1 | 1=允许 Repeated START，0=禁止 |
| 6 | SLAVE_DISABLE | RW | 1 | 1=禁用 Slave 功能（纯 Master 模式） |
| 7 | STOP_DET_IF_MASTER_ACTIVE | RW | 0 | 1=在 Master 传输期间检测 STOP 并触发 R_STP_DET 中断；0=只在 Slave 模式检测 STOP |
| 8 | RX_FIFO_FULL_HLD | RW | 0 | RX FIFO 满时时钟拉伸 |
| [31:9] | Reserved | RO | 0 | 保留 |

> **SPEED 字段占 CON[2:1]（2-bit），非 CON[1] 单独 1-bit。**

### 3.2.x MASTER_MODE + SLAVE_DISABLE 配置组合

| MASTER_MODE | SLAVE_DISABLE | 实际模式 | 说明 |
|-------------|--------------|---------|
| 1 | 1 | **纯 Master** | Controller 只作为 Master 工作，不响应任何地址 |
| 1 | 0 | **双角色（Master+Slave）** | Controller 可做 Master 也可做 Slave |
| 0 | 0 | **纯 Slave** | Controller 只作为 Slave 工作，忽略 Master 命令 |
| 0 | 1 | **保留** | 行为等同于 MASTER_MODE=0, SLAVE_DISABLE=0 |

> **v2.0 建议配置：** 纯 Master 应用使用 MASTER_MODE=1, SLAVE_DISABLE=1；Slave 应用使用 MASTER_MODE=0, SLAVE_DISABLE=0。

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
| [7:0] | DAT | W/RW | 8'h00 | **写：** 待发送数据字节（写入 TX DAT FIFO）<br>**读：** 从 RX FIFO 读取接收数据 |
| 8 | CMD | WO | 1'b0 | **命令位**，写入 TX CMD FIFO：<br>`CMD=0`：写事务（Master 发射数据 / Slave 发射数据）<br>`CMD=1`：读事务（Master 接收数据）<br>Slave 模式下 CMD=0 表示准备发送 |
| [31:9] | Reserved | RO | 0 | 保留 |

**写 DATA_CMD 的行为（DW_apb_i2c 真实行为）：**

写 DATA_CMD 寄存器时，DAT 和 CMD 分别进入两个独立的 FIFO：
```
写入 DATA_CMD{DAT=val, CMD=bit} 时：
  → TX CMD FIFO push CMD bit
  → TX DAT FIFO push DAT byte
```

**TX CMD FIFO 和 TX DAT FIFO 是两条独立的 FIFO**，FIFO 深度均为 16。Master FSM 从两个 FIFO 中**按写入顺序配对消费**：

| TX CMD FIFO | TX DAT FIFO | Master FSM 动作 |
|-------------|-------------|----------------|
| CMD=0（写） | DAT=0xAA | 发起写事务：START→ADDR+W→[0xAA]→STOP |
| CMD=0, CMD=0, CMD=0 | DAT=0x11, 0x22, 0x33 | 连续写 3 字节，自动 STOP |
| CMD=0, CMD=1 | DAT=reg_addr, 0x00 | 写寄存器地址后自动 Repeated START + 读 |
| CMD=1, CMD=1 | DAT=x, x | 连续读 2 字节，最后字节 NACK |

**消费规则：**
- Master 每完成一个字节的发送，从 TX CMD FIFO 弹出一个 CMD，从 TX DAT FIFO 弹出一个 DAT
- TX CMD FIFO 为空时，Master 停止，发送 STOP（或等待新命令）
- 最后 CMD=0 之后自动 STOP；CMD=1 之后自动 STOP（最后字节由 Master 发 NACK）

**读 DATA_CMD 的行为：** 读取 RX FIFO 中的数据（按 FIFO 顺序，先入先出）

**注意：** CMD 和 DAT 必须**成对写入**（每次写寄存器同时填充两个 FIFO），否则 CMD/DAT 配对错乱。

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

#### 3.2.10 I2C_INTR_STAT (0x24) — 中断状态（屏蔽后）

| Bit | 名称 | 描述 |
|-----|------|------|
| 0 | I_RX_FULL | RX FIFO >= RX_TL（屏蔽后） |
| 1 | I_TX_EMPTY | TX FIFO <= TX_TL（屏蔽后） |
| 2 | I_TX_ABRT | 传输中止（屏蔽后） |
| 3 | I_RX_DONE | Slave 接收到 NACK（屏蔽后） |
| 4 | I_RX_OVER | RX FIFO 溢出（屏蔽后） |
| 5 | I_TX_OVER | TX FIFO 溢出（屏蔽后） |
| 6 | I_RD_REQ | Master 请求读 Slave（屏蔽后） |
| 7 | I_TX_EMPTY_HLT | TX FIFO 空且停止发射（屏蔽后） |
| 8 | I_STP_DET | STOP 条件检测（屏蔽后） |
| 9 | I_START_DET | START 条件检测（屏蔽后） |
| 10 | I_ACTIVITY | I2C 总线活动（屏蔽后） |

> **只读**，写操作无效。INTR_STAT = RAW_INTR_STAT & ~INTR_MASK。
> **清除：** 写 1 到 RAW_INTR_STAT (0x28) 对应位可清除（也同步清除 INTR_STAT）。

---

#### 3.2.11 I2C_RAW_INTR_STAT (0x28) — 原始中断状态（屏蔽前）

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

> **只读**，写 1 清零（WC1R），写 0 无效。读取后不清零，必须写 1 清除。

---

#### 3.2.12 I2C_RX_TL (0x2C) — RX FIFO 阈值

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [4:0] | RX_TL | RW | 5'd0 | RX FIFO 触发中断的阈值<br>RX FIFO count >= RX_TL 时 R_RX_FULL=1 |
| [31:5] | Reserved | RO | 0 | 保留 |

---

#### 3.2.13 I2C_TX_TL (0x30) — TX FIFO 阈值

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [4:0] | TX_TL | RW | 5'd0 | TX FIFO 触发中断的阈值<br>TX FIFO count <= TX_TL 时 R_TX_EMPTY=1 |
| [31:5] | Reserved | RO | 0 | 保留 |

---

#### 3.2.14 I2C_ENABLE (0x34) — 使能寄存器

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| 0 | ENABLE | RW | 0 | 1=I2C Controller 使能，0=禁用 |
| 1 | ABORT | RW | 0 | 1=中止当前传输，传输完成后自动清零 |
| [31:2] | Reserved | RO | 0 | 保留 |

---

#### 3.2.15 I2C_STATUS (0x38) — 状态寄存器（只读）

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

#### 3.2.16 I2C_TXFLR (0x3C) — TX FIFO 深度（只读）

| Bit | 名称 | 描述 |
|-----|------|------|------|
| [4:0] | TXFLR | TX FIFO 中当前数据个数 |

---

#### 3.2.17 I2C_RXFLR (0x40) — RX FIFO 深度（只读）

| Bit | 名称 | 描述 |
|-----|------|------|------|
| [4:0] | RXFLR | RX FIFO 中当前数据个数 |

---

#### 3.2.18 I2C_SDA_HOLD (0x44) — SDA 保持时间

| Bit | 名称 | 访问 | 默认 | 描述 |
|-----|------|------|------|------|
| [15:0] | SDA_HOLD | RW | 16'd1 | SCL 下降沿后 SDA 保持周期数 |
| [31:16] | Reserved | RO | 0 | 保留 |

---

#### 3.2.19 I2C_TX_ABRT_SOURCE (0x48) — 传输中止源（只读，清零）

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

#### 3.2.20 I2C_ENABLE_STATUS (0x4C) — Enable 状态（只读）

| Bit | 名称 | 描述 |
|-----|------|------|------|
| 0 | IC_EN | Controller 使能状态（反映 ENABLE.EN） |
| 1 | SLV_ACTIVITY_DISABLED | Slave 活动但被禁用 |
| 2 | MST_ACTIVITY_DISABLED | Master 活动但被禁用 |

---

## 4. 功能描述

### 4.1 整体架构

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          I2C Controller 顶层                              │
│                                                                          │
│  APB Interface              Protocol Engine                   I/O Buffer  │
│  ┌──────────┐              ┌────────────────────┐         ┌───────────┐ │
│  │  Register│◄────────────►│                    │◄────────►│ SCL Gen   │ │
│  │   File   │              │    Master FSM      │         │(Master)   │ │
│  │          │              │    (TX CMD/DAT     │         └─────┬─────┘ │
│  ├──────────┤              │     FIFO Consumer)  │                 │       │
│  │TX CMD FIFO│             │                    │             SCL ──┤       │
│  │ (16×1b) │              │    Slave FSM       │                 │       │
│  │TX DAT FIFO│             │   (addr match,      │         ┌─────┴─────┐ │
│  │ (16×8b) │              │    rx/tx)           │         │  SDA I/O  │ │
│  │RX DAT FIFO│             │                    │◄────────►│           │ │
│  │ (16×8b) │              └────────────────────┘         └───────────┘ │
│  └────┬─────┘                                                         │
│       │ APB                                                              │
│  prdata[31:0]  pwdata[31:0]                    sda_i ◄────────────────┘
│  paddr[7:0]    pwrite                         scl_i ◄────────────────┘
│  psel,penable  presetn                            intr
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 子模块功能划分

| 子模块 | 职责 |
|--------|------|
| **APB Interface** | 寄存器读写译码、FIFO 读/写访问、中断状态管理 |
| **TX CMD FIFO** | 缓存命令位（1-bit/entry，深度 16），决定读/写事务类型 |
| **TX DAT FIFO** | 缓存数据字节（8-bit/entry，深度 16），配合 CMD FIFO 配对消费 |
| **RX FIFO** | 缓存已接收数据，深度 16，提供 full/empty/level 状态 |
| **Master FSM** | 从 TX CMD/DAT FIFO 消费命令，生成 I2C 总线时序（START/ADDR/DATA/ACK/STOP）、仲裁、时钟生成 |
| **Slave FSM** | 地址匹配、接收/发送数据、时钟拉伸响应 |
| **Clock Generator** | 基于 HCNT/LCNT 产生 SCL 时钟（Master 模式） |
| **SDA/SCL I/O Buffer** | 双向 I/O，OE 控制三态，支持上拉电阻（外置） |

### 4.3 Master 写事务（单字节）

```
CPU 操作顺序：
1. 配置 I2C_TAR = 目标地址（7-bit，bit[6:0]）
2. 配置 I2C_CON.MASTER_MODE = 1, SPEED, RESTART_EN
3. 配置 I2C_ENABLE.EN = 1
4. 写 I2C_DATA_CMD{DAT=0xAA, CMD=0}（同时填充 TX CMD FIFO 和 TX DAT FIFO）
5. Master FSM 检测到 TX CMD/DAT FIFO 非空，自动发起事务
6. 轮询 I2C_STATUS.TFE（TX FIFO 空）或等待 TX_EMPTY 中断
7. 读 TX_ABRT_SOURCE 确认无异常

I2C 总线结果：
  S  [ADDR+W] A [0xAA] A  P
  └─START─┘└─地址+写─┘└─数┘└─ACK┘└─STOP─┘

TX FIFO 消费过程：
  写入：TX_CMD=0, TX_DAT=0xAA → FIFO 非空
  Master 消费：START→ADDR+W→[0xAA]→STOP
  FIFO 空：TFE=1
```

### 4.4 Master 连续写事务（多字节）

```
CPU 操作顺序：
1. 配置 I2C_TAR = 目标地址
2. 配置 I2C_ENABLE.EN = 1
3. 连续写入 I2C_DATA_CMD{DAT=val, CMD=0}（3次，填满 TX FIFO）
   写入顺序：{DAT=0x11, CMD=0} → {DAT=0x22, CMD=0} → {DAT=0x33, CMD=0}
4. Master FSM 自动连续消费 TX FIFO：
   - 每消费一对 CMD/DAT，发送一个字节
   - 最后 CMD=0 消费完毕后，自动发送 STOP
5. 轮询 TX_EMPTY 或 TX_ABRT

I2C 总线结果（3字节示例）：
  S [ADDR+W] A [0x11] A [0x22] A [0x33] A  P

关键：CMD 决定"这是数据还是读命令"，Master 按 FIFO 顺序连续发送，
      最后一个写命令后自动 STOP（不需软件干预）
```

### 4.5 Master 读事务（单字节）

```
CPU 操作顺序：
1. 配置 I2C_TAR = 目标地址
2. 配置 I2C_ENABLE.EN = 1
3. 写 I2C_DATA_CMD{DAT=0x00, CMD=1}（CMD=1 表示读）
4. Master FSM 检测到 CMD=1，自动发起读事务
5. 轮询 RX_FULL 中断或读 I2C_STATUS.RFNE
6. 读 I2C_DATA_CMD 获取 RX FIFO 中的数据

I2C 总线结果：
  S [ADDR+R] A [DATA= Slave回] A  NA  P
            └─Master 接收─┘└─ACK─┘└NACK└─STOP─┘

NACK 行为（关键）：
  - 第 8 个 SCL 周期（数据位完成后），Master 驱动 SDA=1（NACK）
  - NACK 是 Master **主动驱动 SDA=1**，不是"释放总线"
  - SCL 第 9 个周期 Master 驱动 SDA=1，同时驱动 SCL=1
  - 随后 Master 发送 STOP（SCL=1 时 SDA 0→1）
```

### 4.6 Master 连续读事务（多字节）

```
CPU 操作顺序：
1. 配置 I2C_TAR = 目标地址
2. 配置 I2C_ENABLE.EN = 1
3. 连续写 I2C_DATA_CMD{DAT=0x00, CMD=1} 三次（3 个读命令）
4. Master FSM 自动执行连续读事务：
   - 前 n-1 个 CMD=1：每接收一字节，Master 驱动 SDA=0（ACK）
   - 最后 1 个 CMD=1：Master 驱动 SDA=1（NACK），随后 STOP
5. 从 RX FIFO 依次读出 3 个数据字节

I2C 总线结果（3字节示例）：
  S [ADDR+R] A [DATA0] A [DATA1] A [DATA2] NA  P
                      ↑Master ACK   ↑Master ACK  ↑Master NACK
```

### 4.7 Master Repeated START（写后读）

```
场景：先写寄存器地址，再 Repeated START 读数据

CPU 操作顺序：
1. 配置 I2C_TAR = 目标地址
2. 配置 I2C_ENABLE.EN = 1
3. 配置 I2C_CON.RESTART_EN = 1
4. 写 I2C_DATA_CMD{DAT=reg_addr, CMD=0}（写寄存器地址）
5. 写 I2C_DATA_CMD{DAT=0x00, CMD=1}（读命令）
6. Master FSM 自动检测：
   - CMD=0 后紧跟 CMD=1 → 在写事务后自动插入 Repeated START
   - 不发 STOP，直接发 Repeated START 再发起读事务
7. 从 RX FIFO 读数据

I2C 总线结果：
  S [ADDR+W] A [REG] A  [ADDR+R] A [DATA] NA  P
              └─写 REG─┘└─RepeatedSTART─┘└─读─

关键机制：
  Master FSM 每次从 TX CMD FIFO 读取 CMD bit：
    - 若当前 CMD=0，下一个 CMD=1 → 不发 STOP，发 Repeated START
    - 若当前 CMD=0，下一个 CMD=0 → 当前字节发送完后，发 STOP
    - 若 CMD=1 → 发 STOP
```

### 4.8 Slave 接收事务

```
配置：
1. 配置 I2C_SAR = 本机地址（7-bit）
2. 配置 I2C_CON.MASTER_MODE=0, SLAVE_DISABLE=0（启用 Slave）
3. 配置 I2C_ENABLE.EN = 1

I2C 总线行为：
- Slave FSM 监听总线，地址匹配后进入 Slave 接收模式
- 在 ACK 时隙自动拉低 SDA（驱动 SDA=0）
- 接收的每个字节存入 RX FIFO
- STOP 检测后退出接收模式

CPU 操作：
1. 等待/轮询 I2C_RAW_INTR_STAT.R_RX_FULL 或 R_STOP_DET
2. 读 I2C_DATA_CMD（连续读出 RX FIFO 中的数据）
3. 处理数据

I2C 总线结果（接收 2 字节）：
  S [ADDR+W] A [DATA0] A [DATA1] A  P
              └─Slave ACK  ──┘└─Slave ACK─┘
```

### 4.9 Slave 发射事务

```
配置：
1. 配置 I2C_SAR = 本机地址（7-bit）
2. 预先写入 TX DAT FIFO（写 DATA_CMD{DAT=val, CMD=0}，至少 1 字节）
3. 配置 I2C_ENABLE.EN = 1

I2C 总线行为：
- 匹配地址 + R/W=1，Slave 进入发射模式
- 从 TX DAT FIFO 取数据驱动 SDA
- 每发送一字节，Master 驱动 ACK/NACK
- Master 发 NACK 后，Slave 检测到总线空闲，结束发射

CPU 操作：
1. 等待/轮询 I2C_RAW_INTR_STAT.R_RD_REQ（Master 请求读）
2. 写 TX DAT FIFO（CMD=0，表示"准备发送数据"）
3. 等待 R_RX_DONE（Master 发送 NACK 表示读事务结束）

I2C 总线结果（Slave 返回 2 字节）：
  S [ADDR+R] A [DATA0] A [DATA1] NA  P
              └─Slave 发射─┘  Master ACK  ↑Master NACK

重要：Slave 模式下，写 DATA_CMD 时 CMD 必须为 0。
      CMD=1 在 Slave 模式下无意义（读事务由 Master 发起）。
```

### 4.10 TX_ABRT 中止条件

| 中止原因 | 说明 |
|---------|------|
| ABRT_7B_NOACK | 地址字节或数据字节发送后，接收方未拉低 SDA（NACK） |
| ABRT_TXDATA_NOACK | 数据字节被 NACK |
| ABRT_ARB_LOST | 总线仲裁失败（两个以上 Master 同时驱动 SDA 产生冲突） |
| ABRT_MASTER_DIS | ENABLE=0 时，Master FSM 仍在尝试驱动总线 |
| ABRT_SLVRD_INTXFR | Slave 收到 Master 的读请求，但 TX DAT FIFO 为空，Slave 无法响应 |
| ABRT_10_NORSTRT | 10-bit 地址模式下，RESTART_EN=0 且 Master 试图发送 Repeated START |

> **TX_ABRT 清零：** 读取 I2C_TX_ABRT_SOURCE 后自动清零。
> **调试建议：** TX_ABRT 发生时，应检查总线连接、目标设备地址、从机是否正确响应。

---

## 5. FIFO 设计

> **FIFO 深度定义：** 所有 FIFO 深度统一由 `parameter DEPTH = 16` 确定（编译时参数，软件运行时不可配）。如需修改，在 RTL 代码中改一处 parameter 即可。

### 5.1 TX FIFO（DW_apb_i2c 真实结构：两条独立 FIFO）

**TX CMD FIFO（命令 FIFO）：**

| 参数 | 值 |
|------|-----|
| 深度 | DEPTH=16（parameter） |
| 宽度 | 1-bit（CMD） |
| 复位 | presetn 异步清零 |
| 满标志 | CMD_FIFO_FULL |
| 空标志 | CMD_FIFO_EMPTY |

**TX DAT FIFO（数据 FIFO）：**

| 参数 | 值 |
|------|-----|
| 深度 | DEPTH=16（parameter） |
| 宽度 | 8-bit（DAT） |
| 复位 | presetn 异步清零 |
| 满标志 | DAT_FIFO_FULL |
| 空标志 | DAT_FIFO_EMPTY |

> **为什么要两条 FIFO？** CMD 决定事务类型（读/写），DAT 携带数据，两者必须按顺序配对。分离后 Master FSM 可以独立判断"下一个是读还是写"，同时灵活处理 Repeated START（CMD=0 紧跟 CMD=1）。

### 5.2 RX FIFO

| 参数 | 值 |
|------|-----|
| 深度 | DEPTH=16（parameter） |
| 宽度 | 8-bit（数据） |
| 复位 | presetn 异步清零 |
| 满标志 | RX_FIFO_FULL |
| 空标志 | RX_FIFO_EMPTY |

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
IDLE          — 空闲，等待 TX CMD FIFO 非空
M_START       — 发送 START + 地址字节
M_ADDR        — 发送地址字节（包含 R/W bit）
M_WDATA       — 发送数据字节
M_RDATA       — 接收数据字节（Master 主动提供时钟）
M_ACK         — 发送 ACK/NACK
M_STOP        — 发送 STOP
M_RESTART     — 发送 Repeated START
```

> **M_IDLE_WAIT 状态已删除（Q12）。TX CMD FIFO 为空时，Master FSM 直接回到 IDLE，不需额外等待状态。**

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

> **地址匹配规则（Q14）：**Slave 使用 7-bit 精确匹配（IC_SAR[6:0] == 接收地址的 bit[7:1]），匹配成功后在 S_ADDR_ACK 状态自动驱动 SDA=0（ACK）。不匹配则保持沉默（高阻）。

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
| v2.2 | 2026-04-26 | Q4~Q14 需求确认：INTR_STAT(0x24)/RAW_INTR_STAT(0x28) 地址拆分、SPEED=CON[2:1] 位定义澄清、MODE 双配置组合表、STOP_DET_IF_MASTER_ACTIVE 含义澄清、Master FSM 删除 M_IDLE_WAIT 状态（直接回 IDLE）、FIFO DEPTH=16 parameter、软件不可配、未定义地址 prdata=0、Slave 7-bit 精确地址匹配规则、寄存器地址表整体前移4字节 |
| v2.1 | 2026-04-26 | 修正 Q1~Q3：TX CMD+DAT 双 FIFO 结构、Master 事务触发机制、NACK 为 Master 主动驱动 SDA=1、Section 2.4 ACK/NACK 方向修正、Section 4.3~4.10 全部事务描述更新 |
| v2.0 | 2026-04-26 | 全新规格，参考 DW_apb_i2c 架构，覆盖 Master+Slave 完整功能，Jack & 小蜂 |
