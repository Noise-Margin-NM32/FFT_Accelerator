import re

with open('self_fft.srcs/sources_1/new/twiddle_rom_512.v', 'r') as f:
    text = f.read()

matches = re.findall(r"8'd\d+:\s*begin\s*wr\s*=\s*16'h([0-9a-fA-F]{4});\s*wi\s*=\s*16'h([0-9a-fA-F]{4});\s*end", text)

with open('twiddles.txt', 'w') as out:
    for wr, wi in matches:
        out.write(f'{wr}{wi}\n')

print(f"Extracted {len(matches)} twiddle factors.")
