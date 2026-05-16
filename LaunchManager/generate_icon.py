from PIL import Image, ImageDraw, ImageFont
import math

size = 1024
img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# macOS icon shape - rounded square
margin = 80
corner_radius = 220

# Draw rounded rectangle background with gradient
for y in range(size):
    ratio = y / size
    r = int(25 + ratio * 15)
    g = int(30 + ratio * 25)
    b = int(70 + ratio * 50)
    
    for x in range(size):
        if x < margin or x >= size - margin or y < margin or y >= size - margin:
            continue
        
        in_rect = True
        # Top-left corner
        if x < margin + corner_radius and y < margin + corner_radius:
            dist = math.sqrt((x - (margin + corner_radius))**2 + (y - (margin + corner_radius))**2)
            if dist > corner_radius:
                in_rect = False
        # Top-right corner
        elif x >= size - margin - corner_radius and y < margin + corner_radius:
            dist = math.sqrt((x - (size - margin - corner_radius))**2 + (y - (margin + corner_radius))**2)
            if dist > corner_radius:
                in_rect = False
        # Bottom-left corner
        elif x < margin + corner_radius and y >= size - margin - corner_radius:
            dist = math.sqrt((x - (margin + corner_radius))**2 + (y - (size - margin - corner_radius))**2)
            if dist > corner_radius:
                in_rect = False
        # Bottom-right corner
        elif x >= size - margin - corner_radius and y >= size - margin - corner_radius:
            dist = math.sqrt((x - (size - margin - corner_radius))**2 + (y - (size - margin - corner_radius))**2)
            if dist > corner_radius:
                in_rect = False
        
        if in_rect:
            img.putpixel((x, y), (r, g, b, 255))

# Draw a gear/cog
cx, cy = size // 2, size // 2 - 20
outer_r = 280
inner_r = 200
hub_r = 90
num_teeth = 8

# Build gear polygon
gear_points = []
for i in range(num_teeth * 2):
    angle = (2 * math.pi * i) / (num_teeth * 2)
    if i % 2 == 0:
        r_val = outer_r
    else:
        r_val = inner_r
    gear_points.append((cx + int(r_val * math.cos(angle)), cy + int(r_val * math.sin(angle))))

draw.polygon(gear_points, fill=(80, 180, 240, 255))

# Inner circle (hub hole)
draw.ellipse([cx - hub_r, cy - hub_r, cx + hub_r, cy + hub_r], fill=(25, 35, 80, 255))

# Draw a rocket/launch arrow in the center
arrow_color = (120, 255, 160, 255)
# Upward pointing arrow
arrow_points = [
    (cx, cy - 60),       # tip
    (cx - 35, cy + 30),  # bottom-left
    (cx - 12, cy + 15),  # inner-left
    (cx - 12, cy + 55),  # tail-left
    (cx + 12, cy + 55),  # tail-right
    (cx + 12, cy + 15),  # inner-right
    (cx + 35, cy + 30),  # bottom-right
]
draw.polygon(arrow_points, fill=arrow_color)

# Save the base icon
base_path = '/Users/jameskaranja/Developer/projects/LaunchdServices/LaunchManager/LaunchManager/Assets.xcassets/AppIcon.appiconset/'

img.save(base_path + 'icon_512x512@2x.png')

# Generate all required sizes
sizes = [16, 32, 128, 256, 512]
for s in sizes:
    resized = img.resize((s, s), Image.LANCZOS)
    resized.save(base_path + f'icon_{s}x{s}.png')
    resized2x = img.resize((s * 2, s * 2), Image.LANCZOS)
    resized2x.save(base_path + f'icon_{s}x{s}@2x.png')

print('All icon sizes generated successfully!')
