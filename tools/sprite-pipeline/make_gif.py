"""Ensambla docs/assets/_frames/f*.png en docs/assets/demo.gif.
Uso: python tools/make_gif.py  (requiere Pillow)
"""
from pathlib import Path
from PIL import Image

frames_dir = Path(__file__).parent.parent / "docs" / "assets" / "_frames"
out = Path(__file__).parent.parent / "docs" / "assets" / "demo.gif"

frames = sorted(frames_dir.glob("f*.png"))
assert frames, f"sin frames en {frames_dir}"

W = 640
imgs = []
for f in frames:
    im = Image.open(f).convert("RGB")
    q = im.quantize(colors=256, method=Image.Quantize.FASTOCTREE,
                    dither=Image.Dither.FLOYDSTEINBERG)
    imgs.append(q.resize((W, int(im.height * W / im.width))))

imgs[0].save(out, save_all=True, append_images=imgs[1:],
             duration=120, loop=0)
print(f"{out} <- {len(imgs)} frames")

for f in frames:
    f.unlink()
frames_dir.rmdir()
