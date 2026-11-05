import os
from PIL import Image

icon_dir = os.path.abspath(os.path.dirname(__file__))
png_files = [
    os.path.join(icon_dir, 'gs_favicon_16.png'),
    os.path.join(icon_dir, 'gs_favicon_32.png'),
    os.path.join(icon_dir, 'gs_favicon_48.png'),
]
ico_path = os.path.join(icon_dir, 'gs_favicon.ico')

imgs = []
for p in png_files:
    try:
        img = Image.open(p)
        imgs.append(img)
    except Exception as e:
        print(f'Error loading {p}: {e}')

if imgs:
    # Pillow can save multi-size ico by passing sizes list
    # Ensure each image is square
    sizes = [(img.width, img.height) for img in imgs]
    # Save first image with sizes list
    try:
        imgs[0].save(ico_path, format='ICO', sizes=sizes)
        print(f'ICO generated at {ico_path} with sizes {sizes}')
    except Exception as e:
        print('Error generating ICO:', e)
else:
    print('No images loaded, cannot generate ICO')

