# Purpose: the game's icon (polish1 item 1): the Lion from the card game's logo (assets/tcg/logo.png), head and mane on a
# gold-rimmed crimson badge -> assets/icon.png (256 px: window / taskbar, project.godot config/icon) and
# assets/icon.ico (16-256 px: the Windows .exe, export_presets.cfg application/icon). Developer-time.
# Dependencies: Pillow; assets/tcg/logo.png. Run: python3 tools/paint_icon.py (from the project folder).
from PIL import Image, ImageDraw, ImageFilter

logo = Image.open("assets/tcg/logo.png").convert("RGBA")
head = logo.crop((280, -5, 740, 395))  # the head and mane only (the leaves and tail are lost at 16 px)
oval = Image.new("L", head.size, 0)
ImageDraw.Draw(oval).ellipse((0, 0, head.width, head.height), fill=255)
head.putalpha(Image.composite(head.getchannel("A"), Image.new("L", head.size, 0), oval.filter(ImageFilter.GaussianBlur(2))))
S = 1024
icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
draw = ImageDraw.Draw(icon)
draw.ellipse((16, 16, S - 16, S - 16), fill=(214, 170, 76, 255))
draw.ellipse((58, 58, S - 58, S - 58), fill=(86, 20, 26, 255))
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse((220, 200, S - 220, S - 220), fill=(170, 60, 40, 170))
icon = Image.alpha_composite(icon, glow.filter(ImageFilter.GaussianBlur(90)))
w = 780
h = int(head.height * w / head.width)
layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
small = head.resize((w, h), Image.LANCZOS)
layer.paste(small, ((S - w) // 2, (S - h) // 2), small)
icon = Image.alpha_composite(icon, layer)
icon.resize((256, 256), Image.LANCZOS).save("assets/icon.png")
icon.save("assets/icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
