% =========================================================
% gen_fft_vectors.m
% Generates fft_input.txt and fft_expected.txt
%
% Matches butterfly_folded.v EXACTLY:
%   State 0: m_rr = B_re * W_re  (32-bit signed multiply)
%            m_ii = B_im * W_im
%            m_ri = B_re * W_im
%            m_ir = B_im * W_re
%   State 1: BW_re = (m_rr - m_ii) >>> 15  -> TRUNCATED TO 16 BITS
%            BW_im = (m_ri + m_ir) >>> 15  -> TRUNCATED TO 16 BITS
%   State 2: ext_A  = sign_extend_17(A)
%            ext_BW = sign_extend_17(BW)   <- from 16-bit truncated value!
%            X_re = (ext_A_re + ext_BW_re) >>> 1
%            Y_re = (ext_A_re - ext_BW_re) >>> 1
% =========================================================

clear; clc;

OUTPUT_DIR = 'D:/meera/Downloads/';
N = 512;
Fs = 8000;

% ----- Helper: truncate to signed 16-bit (models reg signed [15:0]) -----
to_s16 = @(x) double(int16(x));   % clips to [-32768, 32767] with wrap

% ----- Helper: floor divide matching Verilog >>> on signed values -----
asr = @(x, n) floor(x / 2^n);

% ---------------------------------------------------------
% 1. Generate input signal
% ---------------------------------------------------------
t = (0:N-1)' / Fs;
f1 = 440; f2 = 880;
x_real = 0.4*sin(2*pi*f1*t) + 0.3*sin(2*pi*f2*t);

x_re_q = max(min(round(x_real * 32767), 32767), -32768);
x_im_q = zeros(N, 1);

% ---------------------------------------------------------
% 2. Build twiddle table (same floor formula as testbench init_twiddle_ram)
% ---------------------------------------------------------
tw_re = zeros(256, 1);
tw_im = zeros(256, 1);
for n = 0:255
    angle = 2*pi*n/512;
    tw_re(n+1) = max(min(floor(cos(angle)  * 32768), 32767), -32768);
    tw_im(n+1) = max(min(floor(-sin(angle) * 32768), 32767), -32768);
end

% ---------------------------------------------------------
% 3. Emulate hardware FFT bit-exactly
% ---------------------------------------------------------
xr = double(x_re_q);
xi = double(x_im_q);

for s = 1:9
    m  = 2^s;
    m2 = m / 2;
    k  = 0;
    while k < 512
        for j = 0 : m2-1
            tw_idx = j * (512 / m);
            Wr = tw_re(tw_idx + 1);
            Wi = tw_im(tw_idx + 1);

            p = k + j + 1;
            q = k + j + m2 + 1;

            Ar = xr(p);  Ai = xi(p);
            Br = xr(q);  Bi = xi(q);

            % --- State 0: 32-bit multiplies ---
            m_rr = Br * Wr;
            m_ii = Bi * Wi;
            m_ri = Br * Wi;
            m_ir = Bi * Wr;

            % --- State 1: Q15 shift then TRUNCATE TO 16 BITS ---
            % This is the critical step — matches:
            %   reg signed [15:0] BW_re;
            %   BW_re <= (m_rr - m_ii) >>> 15;
            % The assignment to a 16-bit reg silently drops upper bits.
            BWr = to_s16(asr(m_rr - m_ii, 15));
            BWi = to_s16(asr(m_ri + m_ir, 15));

            % --- State 2: 17-bit sign-extend then >>> 1 ---
            % ext_A and ext_BW are sign-extended from their 16-bit values.
            % The >>> 1 on 17-bit result then truncates back to 16 bits.
            % Models: X_re <= (ext_A_re + ext_BW_re) >>> 1
            xr(p) = to_s16(asr(Ar + BWr, 1));
            xi(p) = to_s16(asr(Ai + BWi, 1));
            xr(q) = to_s16(asr(Ar - BWr, 1));
            xi(q) = to_s16(asr(Ai - BWi, 1));
        end
        k = k + m;
    end
end

xr = max(min(xr, 32767), -32768);
xi = max(min(xi, 32767), -32768);

% ---------------------------------------------------------
% 4. Output ordering note:
% The emulation loop processes butterflies in the same order
% as the hardware FSM (same k, j, s loops, same addresses).
% Both hardware and emulation therefore produce outputs in
% the same order — no reordering needed.
% ---------------------------------------------------------
xr_out = xr;
xi_out = xi;

% ---------------------------------------------------------
% 5. Write files using typecast (no uint16 clamping)
% ---------------------------------------------------------
to_u16 = @(x) typecast(int16(x), 'uint16');

fid = fopen([OUTPUT_DIR 'fft_input.txt'], 'w');
for i = 1:N
    fprintf(fid, '%04X %04X\n', to_u16(int16(x_re_q(i))), to_u16(int16(0)));
end
fclose(fid);
fprintf('Written: fft_input.txt\n');

fid = fopen([OUTPUT_DIR 'fft_expected.txt'], 'w');
for i = 1:N
    fprintf(fid, '%04X %04X\n', to_u16(int16(xr_out(i))), to_u16(int16(xi_out(i))));
end
fclose(fid);
fprintf('Written: fft_expected.txt\n');

% ---------------------------------------------------------
% 6. Sanity plot — use natural-order xr/xi for readable plot
% ---------------------------------------------------------
figure;
subplot(2,1,1);
plot(x_re_q); title('Input (Q15)'); xlabel('Sample'); ylabel('Amplitude');

subplot(2,1,2);
mag = abs(xr + 1i*xi);   % natural order for plotting
stem(0:N-1, mag, 'Marker', 'none');
title('Expected FFT magnitude (natural order, before bit-reversal)');
xlabel('Bin'); ylabel('|X[k]|'); grid on;
bin1 = round(f1/Fs * N);
bin2 = round(f2/Fs * N);
hold on;
stem(bin1, mag(bin1+1), 'r', 'LineWidth', 2);
stem(bin2, mag(bin2+1), 'g', 'LineWidth', 2);
legend('All bins', sprintf('f1=%dHz bin%d',f1,bin1), sprintf('f2=%dHz bin%d',f2,bin2));
fprintf('Natural-order peaks at bins %d (%.0fHz) and %d (%.0fHz)\n', bin1, f1, bin2, f2);
fprintf('Hardware stores these at the same indices (DIT in-place).\n');
fprintf('Done!\n');
