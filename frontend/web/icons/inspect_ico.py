import os
from PIL import Image

ico_path = os.path.join(os.path.dirname(__file__), 'gs_favicon.ico')
print('Inspecting ICO at', ico_path)
try:
    im = Image.open(ico_path)
    print('Format:', im.format)
    print('First size:', im.size)
    if hasattr(im, 'info'):
        print('Info dict:', im.info)
    # Attempt to get all sizes via .ico attribute (Pillow 10+?)
    try:
        sizes = im.ico.get_entry_sizes() if hasattr(im, 'ico') else []
        print('ICO entry sizes:', sizes)
    except Exception as e:
        print('Unable to get entry sizes via ico attribute:', e)
except Exception as e:
    print('Error opening ICO:', e)

