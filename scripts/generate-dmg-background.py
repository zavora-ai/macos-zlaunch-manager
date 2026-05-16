from PIL import Image, ImageDraw, ImageFont
import math

# DMG background dimensions (standard is 600x400 or 660x400)
width = 660
height = 440
img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Background gradient - light gray to white
for y in range(height):
    ratio = y / height
    r = int(245 - ratio * 10)
    g = int(247 - ratio * 10)
    b = int(250 - ratio * 8)
    for x in range(width):
        img.putpixel((x, y), (r, g, b, 255))

# Draw a subtle top bar
for y in range(60):
    for x in range(width):
        ratio = y / 60
        r = int(55 + ratio * 30)
        g = int(65 + ratio * 30)
        b = int(95 + ratio * 30)
        img.putpixel((x, y), (r, g, b, 255))

# Load fonts
try:
    title_font = ImageFont.truetype('/System/Library/Fonts/SFCompact.ttf', 22)
    subtitle_font = ImageFont.truetype('/System/Library/Fonts/SFCompact.ttf', 14)
    instruction_font = ImageFont.truetype('/System/Library/Fonts/SFCompact.ttf', 16)
except:
    try:
        title_font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 22)
        subtitle_font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 14)
        instruction_font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 16)
    except:
        title_font = ImageFont.load_default()
        subtitle_font = title_font
        instruction_font = title_font

# Title text in the top bar
draw.text((width // 2, 22), "Launch Manager", fill=(255, 255, 255, 255),
          font=title_font, anchor="mt")
draw.text((width // 2, 44), "macOS launchd Service Manager", fill=(200, 210, 230, 255),
          font=subtitle_font, anchor="mt")

# Draw arrow from app icon position to Applications folder position
# App icon will be at roughly x=440, Applications at x=180
# Arrow goes from right to left
arrow_y = 230
arrow_start_x = 380
arrow_end_x = 260

# Arrow shaft
for thickness in range(-2, 3):
    draw.line([(arrow_start_x, arrow_y + thickness), (arrow_end_x + 15, arrow_y + thickness)],
              fill=(100, 120, 160, 200))

# Arrow head
arrow_points = [
    (arrow_end_x, arrow_y),
    (arrow_end_x + 20, arrow_y - 12),
    (arrow_end_x + 20, arrow_y + 12),
]
draw.polygon(arrow_points, fill=(100, 120, 160, 200))

# Instruction text
draw.text((width // 2, 290), "Drag to Applications to install",
          fill=(80, 90, 110, 255), font=instruction_font, anchor="mt")

# Footer text
draw.text((width // 2, height - 40), "© 2024-2026 Zavora Technologies Ltd",
          fill=(150, 160, 175, 200), font=subtitle_font, anchor="mt")
draw.text((width // 2, height - 22), "Apache License 2.0",
          fill=(150, 160, 175, 180), font=subtitle_font, anchor="mt")

# Save
output_path = '/Users/jameskaranja/Developer/projects/LaunchdServices/scripts/dmg-background.png'
img.save(output_path)

# Also save a @2x version
img_2x = img.resize((width * 2, height * 2), Image.LANCZOS)
img_2x.save('/Users/jameskaranja/Developer/projects/LaunchdServices/scripts/dmg-background@2x.png')

print(f'DMG background saved: {output_path}')
print(f'Size: {width}x{height}')
