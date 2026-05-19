# 🛡️ Kavach 512-Point FFT — Intermediate AHB Integration Phase

Welcome to the **`ahb-integration` branch** of the Kavach 512-Point FFT SoC project. This branch represents **Phase 2 of the 1TOPS initiative development workflow**, focusing on interconnect adaptation and Vivado compiler compatibility.

In this phase, we adapted the open-source VHDL `ag_ahb` interconnect packages and began wiring the dynamic address decoder and arbiter blocks for our SoC target environment.

---

## 🛠️ Accomplishments & Splicing Milestones

### 1. VHDL-to-SystemVerilog Conversion
* **Objective:** Port the high-speed `ag_ahb` VHDL Arbiter and Decoder cores into a SystemVerilog workspace to support advanced multidimensional unpacked ports and interface with our Verilog mathematical modules.
* **Result:** Successfully converted the ports and signals into clean SystemVerilog format.

### 2. Vivado Syntax & Compiler Repairs
During initial compilation, the translated cores threw critical syntax and scope errors in Vivado. We squashed these compiler bugs:
* **The Slice Boundary Bug (`ahb_arbiter.v` Line 116):** 
  * *Error:* Dynamic width slicing (`[2*i+1:2*i]`) inside loop indices failed compilation.
  * *Fix:* Refactored to standard IEEE SystemVerilog constant-width indexed part-selects (`[2*i +: 2]`).
* **The Variable Scope Bug (`ahb_arbiter.v` Line 219):**
  * *Error:* The loop counter integer `idx` was declared inside an unnamed scope block, rendering it invisible to other procedural blocks in Vivado.
  * *Fix:* Hoisted the `idx` declaration to the top of the named `rr_block` scope block.

---

## 📈 Verification Status
* **Core Compiling:** The interconnect arbiter now compiles with zero syntax errors in Vivado!
* **Simulations:** Baseline testbench hooks have been established to verify address phase arbitration.

---
*(Note: To view the baseline mathematical accelerator, switch to the **`main`** branch. To view the final unified SoC including the 16KB custom SRAM and full co-simulation plots, switch to the **`ahb-soc-complete`** branch.)*
