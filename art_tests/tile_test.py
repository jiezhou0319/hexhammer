# 用法: python tile_test.py "贴图路径.png" [裁水印比例]
# 输出 offset_test.png（角对角拼中心看接缝）和 tile2x2.png（四块平铺预览）
import sys
from PIL import Image

path = sys.argv[1]
crop = float(sys.argv[2]) if len(sys.argv) > 2 else 0.92
img = Image.open(path).convert("RGB")
w, h = img.size
img = img.crop((0, 0, int(w * crop), int(h * crop)))  # 默认裁 8% 去水印
W, H = img.size
ox, oy = W // 2, H // 2
off = Image.new("RGB", (W, H))
for dx in (0, -W):
    for dy in (0, -H):
        off.paste(img, (ox + dx, oy + dy))
off.save("offset_test.png")
big = Image.new("RGB", (W * 2, H * 2))
for x in (0, W):
    for y in (0, H):
        big.paste(img, (x, y))
big.thumbnail((1400, 1400))
big.save("tile2x2.png")
print(f"原始 {w}x{h} -> 裁后 {W}x{H}，输出 offset_test.png / tile2x2.png")
