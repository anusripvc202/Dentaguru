import os
from PIL import Image

ico_path = os.path.join(os.path.dirname(__file__), 'gs_favicon.ico')

print('Checking ICO file:', ico_path)
try:
    ico = Image.open(ico_path)
    sizes = []
    for frame in range(ico.n_frames):
        ico.seek(frame)
        sizes.append((ico.width, ico.height))
    print('ICO contains', len(sizes), 'resolution(s):', sizes)
except Exception as e:
    print('Error reading ICO:', e)

