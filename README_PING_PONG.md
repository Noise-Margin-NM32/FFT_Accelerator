# Ping-Pong Buffer FFT Architecture

This branch (`feature/ping-pong-fft`) implements a **Double Buffer (Ping-Pong Buffer)** architecture for the main FFT Data RAM. 

## Why Ping-Pong Buffers?
In a standard single-buffer design, the processor (SoC) and the FFT hardware share one block of memory. This creates a bottleneck:
1. The SoC writes 512 samples.
2. The SoC tells the FFT to start.
3. **The SoC must wait** and cannot write any new incoming data while the FFT is using the memory to compute.

With a **Ping-Pong Buffer**, we use two separate memory blocks (Buffer 0 and Buffer 1).
* While the FFT engine is busy computing the frequency bins in **Buffer 0**, the SoC can simultaneously read the previous results and write new incoming audio/sensor data into **Buffer 1**.
* Once both are done, they "swap" buffers. This allows for **100% continuous, gapless real-time processing**.

## How it works in this code
1. We modified `nm32_fft_top.v` to instantiate two `fft_data_ram` modules instead of one.
2. We introduced a `ping_pong_sel` toggle bit.
3. Every time the SoC writes to the Control Register to pulse the `start` signal, `ping_pong_sel` flips.
   * **If 0:** The SoC's AHB Bus is routed to RAM 0, and the FFT Math Engine is routed to RAM 1.
   * **If 1:** The SoC's AHB Bus is routed to RAM 1, and the FFT Math Engine is routed to RAM 0.

## Programming Model (Software Flow)
To take advantage of this in your C code running on the SoC:
1. **Initial Fill:** Write your first 512 samples to the Data RAM base address.
2. **Start:** Write `1` to the FFT Control Register. The FFT starts processing this frame.
3. **Continuous Loop:**
   * Immediately write your next 512 samples to the Data RAM. (It will automatically route to the second buffer!)
   * Wait for the `DONE` interrupt from the FFT. (This means the FFT finished the *previous* frame).
   * Read the 512 computed results. (You are reading the completed buffer).
   * Write `1` to the FFT Control Register to swap buffers again and start the next computation.
