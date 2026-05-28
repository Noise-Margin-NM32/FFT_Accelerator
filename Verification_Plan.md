# 📋 Kavach FFT Accelerator System Verification Plan (VPlan)

This document outlines the comprehensive verification strategy for the Kavach 512-Point FFT Multi-Slave SoC Interconnect. It ensures both the **mathematical accuracy** of the core and the **protocol compliance** of the AMBA AHB v2.0 bus wrapper.

---

## Phase 1: Block-Level Mathematical Verification (Unit Testing)
**Goal:** Prove the pure Verilog math engine works flawlessly before attaching it to the bus.
* **Golden Model Comparison:** Use a Python/MATLAB script (`NM32_KAVACH.m`) to generate thousands of random audio frames, run a floating-point FFT on them, and convert the outputs to Q15 fixed-point.
* **Test Stimulus:** Apply sine waves, white noise, and impulse spikes.
* **Success Criteria:** The Verilog output must match the MATLAB golden model output with an acceptable quantization error margin (Signal-to-Noise Ratio > 60dB).
* *Status:* ✅ **Completed.**

## Phase 2: Interface & Protocol Verification (AHB Compliance)
**Goal:** Ensure the FFT Wrapper and SRAM never violate AMBA AHB v2.0 specifications.
* **Wait-State Handling:** Have the testbench Master randomly drop `hready` to simulate a busy CPU. Ensure the FFT wrapper doesn't drop data.
* **Address Boundary Checks:** Try to read/write outside the `0x4000` to `0x4BFC` map. Ensure the AHB Arbiter cleanly routes this to the Default Slave and returns an `ERROR` response (`hresp = 01`) instead of crashing the bus.
* **Simultaneous Operations (Hazards):** Test Read-After-Write (RAW) hazards. Have the testbench write an audio sample to SRAM and immediately read it back on the very next clock cycle to ensure the SRAM's internal bypass logic works.

## Phase 3: System-Level Co-Simulation (The Full SoC)
**Goal:** Verify the entire datapath timeline with all components integrated.
* **The "Boot" Sequence:** Verify the CPU successfully loads 256 Twiddle factors into the Twiddle RAM over the bus without corruption.
* **The "Realtime" Handshake:** 
  1. Testbench writes 512 samples to the Data RAM.
  2. Testbench asserts `START`.
  3. Verify the AHB bus drops `hready` if the CPU tries to read the Data RAM *while* the FFT is running.
  4. Verify the `fft_irq` wire physically goes HIGH exactly when the 512th frequency bin is written.
* *Status:* ✅ **Completed.**

## Phase 4: Coverage Metrics (The Commercial Standard)
**Goal:** Prove mathematically that the tests are thorough enough for production silicon.
* **Line Coverage:** Ensure the testbench executes every single line of Verilog code at least once.
* **Toggle Coverage:** Ensure every single wire in the design flips from `0` to `1` and `1` to `0` at least once during the simulation.
* **FSM State Coverage:** Prove that the FFT internal Master FSM successfully transitions through all its states (`IDLE` -> `LOAD` -> `STAGE1` -> ... -> `DONE`).

## Phase 5: Corner Cases & Stress Testing (Breaking the Chip)
**Goal:** Try to intentionally crash the SoC to ensure robust error handling.
* **Zero-Sample Edge Case:** Feed the FFT 512 pure zeros. Ensure it outputs 512 zeros and doesn't get stuck in an infinite loop or throw `X` (unknown) states.
* **Rapid Re-Triggering:** Have the Master write `1` to the `START` register *while* the FFT is already halfway through computing a batch. Ensure the FFT ignores the rogue start command and finishes its current batch without corruption.
* **SRAM Bus Contention:** Rapidly switch between byte, half-word, and word writes to the SRAM boundary lanes to stress test the address decoders.
