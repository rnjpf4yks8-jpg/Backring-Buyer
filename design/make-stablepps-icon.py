import sys, numpy as np, cairosvg, io
from PIL import Image, ImageFilter
width_frac = float(sys.argv[1]); out = sys.argv[2]
N = 2048  # draw at 2x, then shrink for smooth edges
bg_svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
<defs><radialGradient id="bg" cx="50%" cy="38%" r="75%"><stop offset="0" stop-color="#2B7A52"/><stop offset="1" stop-color="#0E3221"/></radialGradient>
<linearGradient id="gold" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#F9DD80"/><stop offset="0.55" stop-color="#E2B441"/><stop offset="1" stop-color="#B8862A"/></linearGradient></defs>
<rect width="1024" height="1024" fill="url(#bg)"/>
<circle cx="512" cy="512" r="380" fill="none" stroke="url(#gold)" stroke-width="44"/>
<circle cx="512" cy="512" r="334" fill="none" stroke="#F9DD80" stroke-opacity="0.3" stroke-width="6"/></svg>'''
bg = Image.open(io.BytesIO(cairosvg.svg2png(bytestring=bg_svg.encode(), output_width=N, output_height=N))).convert('RGB')

mask = Image.open('horse-silhouette.png').convert('L')
mask = mask.crop(mask.getbbox()).filter(ImageFilter.GaussianBlur(2.2))
target_w = int(N * width_frac)
target_h = int(mask.height * target_w / mask.width)
mask = mask.resize((target_w, target_h), Image.LANCZOS)
a = np.array(mask).astype(float) / 255
a = np.clip((a - 0.5) * 3 + 0.5, 0, 1)  # crisp but anti-aliased edge

# gold gradient across the horse, light top-left to deep bottom-right
yy, xx = np.mgrid[0:target_h, 0:target_w]
t = (xx / target_w * 0.6 + yy / target_h * 0.4)
c0, c1, c2 = np.array([249, 221, 128]), np.array([226, 180, 65]), np.array([184, 134, 42])
t3 = t[..., None]
gold = np.where(t3 < 0.55, c0 + (c1 - c0) * (t3 / 0.55), c1 + (c2 - c1) * ((t3 - 0.55) / 0.45))

# thin dark-green edge so the horse stands off the background
edge = np.array(mask.filter(ImageFilter.MaxFilter(9))).astype(float) / 255
edge = np.clip((edge - 0.5) * 3 + 0.5, 0, 1)

canvas = np.array(bg).astype(float)
x0 = (N - target_w) // 2
y0 = (N - target_h) // 2 + int(N * 0.012)   # a touch low: hooves carry the visual weight
pad = 8
region = canvas[y0:y0 + target_h, x0:x0 + target_w]
dark = np.array([14, 50, 33])
region[:] = region * (1 - edge[..., None]) + dark * edge[..., None]
region[:] = region * (1 - a[..., None]) + gold * a[..., None]
img = Image.fromarray(canvas.clip(0, 255).astype('uint8')).resize((1024, 1024), Image.LANCZOS)
img.save(out)
