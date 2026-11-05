import os
from PIL import Image

ico_path = os.path.join(os.path.dirname(__file__), 'gs_favicon.ico')
print('Opening ICO:', ico_path)
try:
    im = Image.open(ico_path)
    sizes = []
    i = 0
    while True:
        sizes.append(im.size)
        i += 1
        try:
            im.seek(i)
        except EOFError:
            break
    print('Found', len(sizes), 'icon size(s):', sizes)
except Exception as e:
    print('Error reading ICO:', e)

