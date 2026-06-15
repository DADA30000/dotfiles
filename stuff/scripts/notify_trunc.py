import sys
import gi
import cairo  # We import the actual python module, not via gi

# Fix the warning by specifying versions first
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")

from gi.repository import Pango, PangoCairo  # noqa: E402


def truncate_to_fit(text, font_desc, max_width_px):
    # Use the 'cairo' module directly for the surface
    surface = cairo.ImageSurface(cairo.Format.ARGB32, 0, 0)
    context = cairo.Context(surface)

    layout = PangoCairo.create_layout(context)
    layout.set_font_description(Pango.FontDescription(font_desc))

    # Check full width first
    layout.set_text(text, -1)
    width, _ = layout.get_pixel_size()

    # Pango pixels are 1024 units.
    # We convert to standard pixels for comparison.
    # However, get_pixel_size returns device units (standard pixels),
    # so we compare directly.
    if width <= max_width_px:
        return text

    # Binary search for the perfect cut point
    low = 0
    high = len(text)
    best_fit = text[:1] + "..."  # Default fallback

    while low <= high:
        mid = (low + high) // 2
        candidate = text[:mid] + "..."
        layout.set_text(candidate, -1)
        w, _ = layout.get_pixel_size()

        if w <= max_width_px:
            best_fit = candidate
            low = mid + 1
        else:
            high = mid - 1

    return best_fit


if __name__ == "__main__":
    # Simple usage check
    if len(sys.argv) < 3:
        print("Usage: ./script.py <MAX_PX> <FONT> <LINE1> [LINE2 ...]")
        sys.exit(1)

    max_px = int(sys.argv[1])
    font = sys.argv[2]

    # Process all remaining arguments as separate lines
    for line in sys.argv[3:]:
        print(truncate_to_fit(line, font, max_px))
