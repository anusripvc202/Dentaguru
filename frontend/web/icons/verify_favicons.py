import os
from PIL import Image

icon_dir = os.path.dirname(__file__)
png_pattern = 'gs_favicon_*.png'
ico_file = os.path.join(icon_dir, 'gs_favicon.ico')

print('PNG dimensions:')
for fname in sorted([f for f in os.listdir(icon_dir) if f.startswith('gs_favicon_') and f.endswith('.png')]):
    path = os.path.join(icon_dir, fname)
    try:
        im = Image.open(path)
        print(f'{fname}: {im.width}x{im.height}')
    except Exception as e:
        print(f'Error opening {fname}: {e}')

print('\nICO file info:')
try:
    ico = Image.open(ico_file)
    # PIL may provide the sizes attribute for ICO
    sizes = ico.ico.getentrysizes() if hasattr(ico, 'ico') else []
    # fallback: attempt to read frames
    try:
        while True:
            sizes.append((ico.width, ico.height))
            ico.seek(ico.tell() + 1)
    except EOFError:
        pass
    print(f'Found {len(sizes)} resolution(s) in ICO: {sizes}')
except Exception as e:
    print(f'Error reading ICO: {e}')

