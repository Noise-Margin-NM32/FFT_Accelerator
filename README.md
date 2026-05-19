# 🛡️ Kavach 512-Point FFT Accelerator Core with AHB Wrapper

Welcome to the **main branch** of the **Kavach 512-Point FFT Accelerator Core**. This repository represents the baseline, self-contained processing block developed as part of the **1TOPS initiative by the VLSI Society of India**.

This branch contains the standalone **512-Point Cooley-Tukey DIT pipelined mathematical engine** integrated with an AMBA AHB protocol wrapper interface.

---

## ⏱️ The Silicon Timeline: From Power-On to First Execution

This timeline documents the cycle-accurate electrical data flows and state transitions of the accelerator core during operations:

### 1. The Clean Slate (Power-On Reset)
* **The Action:** The moment the device turns on, the SoC system controller asserts your `rst` (reset) pin high.
* **The Result:** Your Master FSM snaps into State 0 (Idle). All internal tracking loops (stages, butterfly counters) are wiped to zero. The `done` flag is pulled low. The chip is awake but waiting.

### 2. The Boot Sequence (Loading the Constants)
* **The Action:** The SoC’s main bootloader reads the pre-calculated complex sine/cosine numbers from the device's main flash storage.
* **The Data Flow:** The bootloader drives the pins for your newly added Twiddle RAM (Scratchpad B). Over the course of 256 clock cycles, it writes the trigonometry constants into memory.
* **The Result:** Your internal "reference manual" is fully populated. Scratchpad B is now locked.

### 3. The Audio Collection (Loading the Warehouse)
* **The Action:** The user speaks into the microphone. The SoC’s DMA (Direct Memory Access) controller takes over. It sets your `ext_we` (Write Enable) pin to HIGH.
* **The Data Flow:**
  * **Tick 1:** DMA sets `ext_addr` to `0` and pushes the first audio sample onto `ext_din`. Scratchpad A saves it.
  * **Tick 2:** DMA changes `ext_addr` to `1` and pushes the second sample onto `ext_din`. Scratchpad A saves it.
  * *(This repeats exactly 512 times as the audio frame fills up).*
* **Time Elapsed:** ~2.84 microseconds (512 clock cycles).

### 4. The Handover (Passing the Baton)
* **The Action:** The DMA has finished delivering the 512 audio samples. It drops `ext_we` to LOW.
* **The Data Flow:** On the very next clock cycle, the DMA pulses your `start` pin to HIGH for exactly one tick.
* **The Result:** Your Master FSM detects the start pulse. It immediately disconnects the RAM from the external pins. The workshop doors are now locked.

### 5. The First Butterfly (The Math Begins)
The FSM is now in total control. It initiates Stage 1 of the FFT, targeting the very first pair of audio samples.
* **Tick N (The 3-Way Read):**
  * The FSM points internal `addr_a` to slot `0` and `addr_b` to slot `1`.
  * It calculates the twiddle index and points to angle `0` in Scratchpad B.
  * **Data Flow:** Both audio samples and the exact trigonometry angle flow out of the memories and hit the input pins of the `butterfly_folded` module simultaneously.
* **Tick N+1 (Multiplication):** The Butterfly FSM wakes up. It fires its four 32-bit hardware multipliers to calculate $B \times W$ (Real and Imaginary components).
* **Tick N+2 (Truncation):** The 32-bit multiplied results are bit-shifted down to 16-bit Q15 format to prevent data bloat (division by $2^{15}$).
* **Tick N+3 (Addition/Subtraction):** The 17-bit sign-extended adders fire. They calculate $X = A + BW$ and $Y = A - BW$ simultaneously, safely avoiding any overflow clipping.
* **Tick N+4 (The Overwrite):**
  * The Butterfly finishes the math, bit-shifts back to 16 bits, and pulses its internal done flag.
  * **Data Flow:** The Master FSM sees the flag. Without moving its memory pointers, it pulses the internal write enables (`we_a` and `we_b`). The new frequencies $X$ and $Y$ instantly overwrite the original raw audio sitting in Scratchpad A at slots `0` and `1`.
* **Subsequent Butterflies:** The very first butterfly operation is now complete. The Master FSM immediately increments its counters to address `2` and `3`, and the assembly line fires up again. This will happen 2,303 more times until the `done` pin is finally raised for the outside world.

---

## 🛠️ Baseline Core Modules
1. **nm32_fft_top.v:** The primary FSM and Cooley-Tukey stage index controller.
2. **fft_data_ram.v (Scratchpad A):** The 2KB dual-port high-speed data memory block.
3. **twiddle_rom_512.v (Scratchpad B):** The reference look-up memory for trigonometry coefficients.
4. **butterfly_folded.v:** The 5-cycle pipelined mathematical butterfly execution unit.
5. **nm32_fft_ahb_wrapper.v:** The AHB protocol interface layer developed as part of the core accelerator.

---
*(Note: To view the full SoC system integration including the 16KB general Scratchpad SRAM and central AHB Decoder/Arbiter, please switch to the **`ahb-soc-complete`** branch.)*
