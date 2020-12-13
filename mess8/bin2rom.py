import sys
from PIL import Image

src = None
with open(sys.argv[1], "rb") as f:
    src = f.read()

num_bytes = len(src)

rom_byte_img = Image.open("rom_byte.png")
output_img = Image.new("RGB", (rom_byte_img.width, rom_byte_img.height * num_bytes))

for i in range(num_bytes):
    output_img.paste(rom_byte_img, (0, rom_byte_img.height * i))

for y, byte in enumerate(src):
    for x in range(8):
        if (byte & (1 << x)) != 0:
            output_img.putpixel((29 - 4 * x, rom_byte_img.height * y + 1), (255, 255, 255))

output_img.save(sys.argv[1].replace(".bin", ".png"))

