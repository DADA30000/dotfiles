import math
from PIL import Image


def get_closest_nixos_color(r, g, b):
    """
    Finds the closest official NixOS brand color using Euclidean distance.
    This works perfectly when applied to the unblended mask-filtered pixels.
    """
    dark_blue = (82, 119, 195)  # #5277C3 (Royal Blue)
    light_blue = (126, 186, 228)  # #7EBAE4 (Sky Blue)

    dist_dark = (r - 82) ** 2 + (g - 119) ** 2 + (b - 195) ** 2
    dist_light = (r - 126) ** 2 + (g - 186) ** 2 + (b - 228) ** 2

    return dark_blue if dist_dark < dist_light else light_blue


def get_cell_color(
    bx, by, img, high_res_binary, img_color_resized, width, height
):
    """
    Scans the entire high-res area of the cell and averages ONLY the pixels
    that are part of the logo (where high_res_binary == 0). This completely
    filters out the white background, preventing any color blending bias.
    """
    # Calculate the high-res cell boundaries
    x1 = int(bx * (img.width / width))
    x2 = int((bx + 1) * (img.width / width))
    y1 = int(by * (img.height / height))
    y2 = int((by + 1) * (img.height / height))

    logo_colors = []

    # Scan every pixel in this cell's high-res block
    for py in range(y1, y2):
        for px in range(x1, x2):
            if 0 <= px < img.width and 0 <= py < img.height:
                # If it's a logo pixel (0) and not background (255)
                if high_res_binary.getpixel((px, py)) == 0:
                    logo_colors.append(img.getpixel((px, py)))

    if logo_colors:
        # Average the pure logo colors in this cell
        avg_r = sum(c[0] for c in logo_colors) // len(logo_colors)
        avg_g = sum(c[1] for c in logo_colors) // len(logo_colors)
        avg_b = sum(c[2] for c in logo_colors) // len(logo_colors)
        return avg_r, avg_g, avg_b

    # Fallback to nearest-neighbor if the entire patch is white (failsafe)
    return img_color_resized.getpixel((bx, by))


def create_polished_outline(
    image_path,
    width=55,
    vertical_scale=0.48,
    binarize_threshold=200,
    thickness_threshold=165,
    mode="braille",
    fill=False,
):
    """
    Converts an image into a sharp, colored thin-outline ASCII art.
    Uses high-res mask-filtered sampling to prevent color bleed,
    and a thickness threshold of 165 to close up diagonal gaps.
    """
    try:
        img = Image.open(image_path)
    except Exception as e:
        print(f"Error opening image: {e}")
        return

    # 1. Handle transparency by rendering onto a solid white background
    if img.mode in ("RGBA", "LA") or (
        img.mode == "P" and "transparency" in img.info
    ):
        bg = Image.new("RGBA", img.size, (255, 255, 255, 255))
        bg.paste(img, (0, 0), img.convert("RGBA"))
        img = bg.convert("RGB")
    else:
        img = img.convert("RGB")

    # 2. Add safety padding (6% margin) to prevent top/bottom cuts
    padding_w = max(4, int(img.width * 0.06))
    padding_h = max(4, int(img.height * 0.06))
    padded_size = (img.width + 2 * padding_w, img.height + 2 * padding_h)
    padded_img = Image.new("RGB", padded_size, (255, 255, 255))
    padded_img.paste(img, (padding_w, padding_h))
    img = padded_img

    # 3. Create a perfect high-res binary image first
    gray_high_res = img.convert("L")
    high_res_binary = gray_high_res.point(
        lambda p: 0 if p < binarize_threshold else 255
    )

    # 4. Calculate target height (with vertical_scale compensation)
    aspect_ratio = img.height / img.width
    height = int(width * aspect_ratio * vertical_scale)

    # 5. Create a downscaled color image as a fallback reference
    img_color_resized = img.resize((width, height), Image.Resampling.NEAREST)

    if mode == "braille":
        sub_w = width * 2
        sub_h = height * 4

        # Downscale the locked binary mask using BILINEAR directly (no blur)
        img_resized = high_res_binary.resize(
            (sub_w, sub_h), Image.Resampling.BILINEAR
        )
        binary = img_resized.point(
            lambda p: 0 if p < thickness_threshold else 255
        )

        # Find edges/shapes in the subpixel grid (ignoring the absolute outer 1-pixel margin)
        edge_mask = [[False for _ in range(sub_w)] for _ in range(sub_h)]
        for y in range(1, sub_h - 1):
            for x in range(1, sub_w - 1):
                if binary.getpixel((x, y)) == 0:
                    if fill:
                        # Solid fill mode: all interior logo pixels are active
                        edge_mask[y][x] = True
                    else:
                        # Outline mode: only edge pixels are active
                        n_l = binary.getpixel((x - 1, y))
                        n_r = binary.getpixel((x + 1, y))
                        n_t = binary.getpixel((x, y - 1))
                        n_b = binary.getpixel((x, y + 1))

                        # A dot is on the edge if it touches any background dot (255)
                        if (
                            n_l == 255
                            or n_r == 255
                            or n_t == 255
                            or n_b == 255
                        ):
                            edge_mask[y][x] = True

        # Map 2x4 binary subgrids to Braille Unicode points with color
        ascii_rows = []
        for by in range(height):
            row = []
            for bx in range(width):
                offset = 0
                dots = [
                    (0, 0, 1),  # Dot 1 (top-left)
                    (0, 1, 2),  # Dot 2
                    (0, 2, 4),  # Dot 3
                    (1, 0, 8),  # Dot 4 (top-right)
                    (1, 1, 16),  # Dot 5
                    (1, 2, 32),  # Dot 6
                    (0, 3, 64),  # Dot 7 (bottom-left)
                    (1, 3, 128),  # Dot 8 (bottom-right)
                ]
                for x_dot, y_dot, val in dots:
                    px = bx * 2 + x_dot
                    py = by * 4 + y_dot
                    if px < sub_w and py < sub_h:
                        if edge_mask[py][px]:
                            offset += val

                if offset == 0:
                    row.append(" ")
                else:
                    char = chr(0x2800 + offset)
                    # Sample the unblended logo color by averaging only active high-res logo pixels
                    r, g, b = get_cell_color(
                        bx,
                        by,
                        img,
                        high_res_binary,
                        img_color_resized,
                        width,
                        height,
                    )
                    color = get_closest_nixos_color(r, g, b)
                    # Wrap in standard 24-bit True Color (RGB) ANSI escape sequence
                    row.append(
                        f"\x1b[38;2;{color[0]};{color[1]};{color[2]}m{char}\x1b[0m"
                    )
            ascii_rows.append("".join(row))
        return "\n".join(ascii_rows)

    elif mode == "unicode_rich":
        # Downscale using BILINEAR directly (no blur)
        img_resized = high_res_binary.resize(
            (width, height), Image.Resampling.BILINEAR
        )
        binary = img_resized.point(
            lambda p: 0 if p < thickness_threshold else 255
        )

        ascii_rows = []
        for y in range(1, height - 1):
            row = []
            for x in range(1, width - 1):
                current_val = binary.getpixel((x, y))

                if current_val == 0:
                    gray_l = img_resized.getpixel((x - 1, y))
                    gray_r = img_resized.getpixel((x + 1, y))
                    gray_t = img_resized.getpixel((x, y - 1))
                    gray_b = img_resized.getpixel((x, y + 1))

                    dx = gray_r - gray_l
                    dy = gray_b - gray_t

                    is_edge = False
                    if abs(dx) >= abs(dy):
                        is_edge = (
                            binary.getpixel((x + 1, y)) == 255
                            or binary.getpixel((x - 1, y)) == 255
                        )
                    else:
                        is_edge = (
                            binary.getpixel((x, y + 1)) == 255
                            or binary.getpixel((x, y - 1)) == 255
                        )

                    if is_edge:
                        angle = math.degrees(math.atan2(dy, dx)) % 180

                        if 22.5 <= angle < 67.5:
                            char = "╱"
                        elif 67.5 <= angle < 112.5:
                            if dy < 0:
                                char = "‾"
                            elif dy > 0:
                                char = "_"
                            else:
                                char = "─"
                        elif 112.5 <= angle < 157.5:
                            char = "╲"
                        else:
                            char = "│"

                        r, g, b = img_color_resized.getpixel((x, y))
                        color = get_closest_nixos_color(r, g, b)
                        # Wrap in standard 24-bit True Color (RGB) ANSI escape sequence
                        row.append(
                            f"\x1b[38;2;{color[0]};{color[1]};{color[2]}m{char}\x1b[0m"
                        )
                    else:
                        row.append(" ")
                else:
                    row.append(" ")
            ascii_rows.append("".join(row))
        return "\n".join(ascii_rows)


if __name__ == "__main__":
    image_file = "nixos_logo.png"

    # Strictly Braille mode
    selected_mode = "braille"

    # Set to True for a solid filled logo, or False for a hollow outline
    fill_mode = True

    ascii_art = create_polished_outline(
        image_file,
        width=55,
        vertical_scale=0.48,  # 0.48 for your preferred vertical ratio
        binarize_threshold=200,
        thickness_threshold=165,
        mode=selected_mode,
        fill=fill_mode,
    )

    if ascii_art:
        print(ascii_art)
        with open("outline_ascii.txt", "w", encoding="utf-8") as f:
            f.write(ascii_art)
