% =========================================================================
% NM32 kavach - Hardware vs Golden Model Co-Simulation
% Roll Number: EC23I2015
% =========================================================================

clear; clc; close all;

% --- DEFINE ABSOLUTE PATHS ---
base_dir = 'C:\Users\ragha\Desktop\IIITDM\';
audio_in_path = fullfile(base_dir, 'audio_in.txt');
fft_out_path  = fullfile(base_dir, 'fft_out.txt');

%% PART 1: GENERATE PCM AUDIO INPUT
fs = 16000;           % 16 kHz microphone sampling rate
N = 512;              % 512-point audio frame
t = (0:N-1) / fs;     % Time vector for one frame (32 ms)

% Create a composite signal: Safe Speech (500 Hz) + Trigger Noise (4000 Hz)
safe_tone = 0.5 * sin(2 * pi * 500 * t);
trigger_noise = 0.5 * sin(2 * pi * 4000 * t);
audio_in = safe_tone + trigger_noise;

% Convert to 16-bit Q15 format (The exact values sent to hardware)
audio_in_quantized = round(audio_in * 32767);

% Handle Two's Complement for the Hex file
q15_audio_hex = audio_in_quantized;
q15_audio_hex(q15_audio_hex < 0) = q15_audio_hex(q15_audio_hex < 0) + 65536;

% Write to absolute path (Format: 32-bit Hex -> [Real 16-bit][Imag 16-bit])
fid_in = fopen(audio_in_path, 'w');
for i = 1:N
    fprintf(fid_in, '%04X0000\n', q15_audio_hex(i));
end
fclose(fid_in);

fprintf('Step 1 Complete: audio_in.txt generated at %s\n', audio_in_path);
disp('-> NOW RUN YOUR VERILOG TESTBENCH <-');
disp('Press any key once you have copied fft_out.txt back to this folder...');
pause;

%% PART 2: ANALYZE HARDWARE FFT OUTPUT
fid_out = fopen(fft_out_path, 'r');
if fid_out == -1
    error(['Cannot find fft_out.txt at ', fft_out_path, '. Did you copy it from Vivado?']);
end

hw_fft_data = textscan(fid_out, '%s');
fclose(fid_out);
hw_fft_hex = hw_fft_data{1};

hw_fft_complex = zeros(1, N);

for i = 1:N
    hex_str = hw_fft_hex{i};
    re_hex = hex_str(1:4);
    im_hex = hex_str(5:8);
    
    re_dec = hex2dec(re_hex);
    im_dec = hex2dec(im_hex);
    
    if re_dec >= 32768, re_dec = re_dec - 65536; end
    if im_dec >= 32768, im_dec = im_dec - 65536; end
    
    hw_fft_complex(i) = re_dec + 1i * im_dec;
end

% Unscramble the hardware Bit-Reversed addresses
bit_rev_indices = bin2dec(fliplr(dec2bin(0:N-1, log2(N)))) + 1;
hw_fft_sorted = hw_fft_complex(bit_rev_indices);
hw_magnitude = abs(hw_fft_sorted);

%% PART 3: THE GOLDEN MODEL (MATLAB FFT)
% Run MATLAB's perfect floating-point FFT on the exact same quantized input
sw_fft_complex = fft(audio_in_quantized, N);
sw_magnitude = abs(sw_fft_complex);

%% PART 4: PLOT THE COMPARISON
f_axis = (0:N-1) * (fs / N);

figure('Name', 'NM32 kavach: Hardware vs Golden Model', 'Position', [100, 100, 900, 600]);

% --- TOP GRAPH: MATLAB Golden Model ---
subplot(2,1,1);
plot(f_axis(1:N/2), sw_magnitude(1:N/2), 'r', 'LineWidth', 1.5);
title('Golden Model: MATLAB Built-in FFT (Floating-Point)');
xlabel('Frequency (Hz)');
ylabel('Magnitude');
grid on;
xlim([0 fs/2]);

% --- BOTTOM GRAPH: Verilog Hardware Output ---
subplot(2,1,2);
plot(f_axis(1:N/2), hw_magnitude(1:N/2), 'b', 'LineWidth', 1.5);
title('NM32 kavach Silicon: Verilog Hardware Output (16-bit Fixed-Point)');
xlabel('Frequency (Hz)');
ylabel('Magnitude');
grid on;
xlim([0 fs/2]);

disp('Verification Complete. Compare the top and bottom graphs.');
