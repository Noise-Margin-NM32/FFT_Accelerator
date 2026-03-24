`timescale 1ns / 1ps

module fft_data_ram (
    input wire clk,
    
    // Port A Used for Sample A/X output
    input wire we_a,              // Write Enable A
    input wire [8:0] addr_a,      // 9 bit address for 512 points
    input wire [31:0] din_a,      // 32 bit input (16-bit Real + 16-bit Imag)
    output reg [31:0] dout_a,     // 32 bit output
    
    // Port B (Used for Sample B / Y output)
    input wire we_b,              // Write Enable B
    input wire [8:0] addr_b,      // 9 bit address for 512 points
    input wire [31:0] din_b,      // 32 bit input (16-bit Real + 16-bit Imag)
    output reg [31:0] dout_b      // 32 bit output
);

    reg [31:0] ram [0:511];

    // Port A Operation Synchronous Read/Write
    always @(posedge clk) begin
        if (we_a) begin
            ram[addr_a] <= din_a;
            dout_a <= din_a;      // Write-first behavior
        end else begin
            dout_a <= ram[addr_a];
        end
    end

    // Port B Operation (Synchronous Read/Write)
    always @(posedge clk) begin
        if (we_b) begin
            ram[addr_b] <= din_b;
            dout_b <= din_b;      // Write-first behavior
        end else begin
            dout_b <= ram[addr_b];
        end
    end

endmodule
