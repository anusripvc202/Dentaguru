import os
from PIL import Image, ImageDraw, ImageFont

def make_background_transparent(input_path, output_path, threshold=230):
    img = Image.open(input_path).convert("RGBA")
    datas = img.getdata()

    new_data = []
    for item in datas:
        # Check if the pixel is near-white / background color
        if item[0] >= threshold and item[1] >= threshold and item[2] >= threshold:
            new_data.append((255, 255, 255, 0))  # Completely transparent
        else:
            new_data.append(item)

    img.putdata(new_data)
    
    # Bounding box crop to remove excess empty padding around logo graphic
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)

    img.save(output_path, "PNG")
    print(f"Successfully processed transparent logo at {output_path}")

def generate_fallback_transparent_logo(output_path):
    width, height = 900, 280
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0)) # 100% Transparent
    draw = ImageDraw.Draw(img)

    # 1. Draw 3D Blue Emblem Container with Tooth Cutout
    # Main D shape
    draw.rounded_rectangle([10, 10, 250, 270], radius=45, fill=(0, 82, 204, 255))
    
    # Tooth Shape cutout inside D (white tooth)
    draw.ellipse([70, 55, 140, 140], fill=(255, 255, 255, 255))
    draw.ellipse([120, 55, 190, 140], fill=(255, 255, 255, 255))
    draw.polygon([(70, 95), (190, 95), (175, 220), (140, 175), (130, 175), (85, 220)], fill=(255, 255, 255, 255))

    # Orbital Ring Swoosh
    draw.arc([0, 100, 260, 180], start=160, end=380, fill=(0, 140, 255, 255), width=10)

    # 2. Draw Typography ("enta" in Navy #0052CC, "Guru" in Vibrant Orange #FF7A00)
    font_path = "C:\\Windows\\Fonts\\arialbd.ttf"
    if not os.path.exists(font_path):
        font_path = "C:\\Windows\\Fonts\\segoeui.ttf"
        
    font_large = ImageFont.truetype(font_path, 130)

    draw.text((265, 60), "enta", font=font_large, fill=(0, 82, 204, 255))
    draw.text((535, 60), "Guru", font=font_large, fill=(255, 122, 0, 255))

    img.save(output_path, "PNG")

if __name__ == "__main__":
    ai_logo_src = r"C:\Users\ADMIN\.gemini\antigravity-ide\brain\6fe898bb-194c-46da-be00-19933bee3f12\dentaguru_official_logo_1785411908674.png"
    
    targets = [
        r"c:\Users\ADMIN\Desktop\project tpc\Dentaguru\dentaguru_logo.png",
        r"c:\Users\ADMIN\Desktop\project tpc\Dentaguru\frontend\assets\dentaguru_logo.png",
        r"c:\Users\ADMIN\Desktop\project tpc\Dentaguru\frontend\build\flutter_assets\assets\dentaguru_logo.png",
        r"c:\Users\ADMIN\Desktop\project tpc\Dentaguru\frontend\web\favicon.png",
        r"c:\Users\ADMIN\Desktop\project tpc\Dentaguru\frontend\web\icons\Icon-192.png",
        r"c:\Users\ADMIN\Desktop\project tpc\Dentaguru\frontend\web\icons\Icon-512.png"
    ]
    
    if os.path.exists(ai_logo_src):
        for tgt in targets:
            os.makedirs(os.path.dirname(tgt), exist_ok=True)
            make_background_transparent(ai_logo_src, tgt, threshold=220)
    else:
        for tgt in targets:
            os.makedirs(os.path.dirname(tgt), exist_ok=True)
            generate_fallback_transparent_logo(tgt)
