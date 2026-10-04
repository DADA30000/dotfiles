import glob
import os
import tomllib

colors = [
    ("#00FF00", "#000000"),
    ("#0000FF", "#0057d1"),
    ("#FF0000", "#000000"),
]

hotspots = {
    "bottom_left_corner": (0.06, 0.88),
    "bottom_right_corner": (0.88, 0.88),
    "bottom_side": (0.50, 0.88),
    "bottom_tee": (0.50, 0.88),
    "center_ptr": (0.44, 0.06),
    "circle": (0.19, 0.06),
    "context-menu": (0.19, 0.06),
    "copy": (0.19, 0.06),
    "dnd-ask": (0.38, 0.25),
    "dnd-copy": (0.38, 0.25),
    "dnd-link": (0.38, 0.25),
    "dnd_no_drop": (0.38, 0.25),
    "grabbing": (0.50, 0.25),
    "hand1": (0.56, 0.25),
    "hand2": (0.44, 0.06),
    "left_ptr": (0.19, 0.06),
    "left_ptr_watch": (0.19, 0.06),
    "left_side": (0.06, 0.50),
    "left_tee": (0.88, 0.50),
    "link": (0.19, 0.06),
    "ll_angle": (0.06, 0.81),
    "lr_angle": (0.88, 0.88),
    "pencil": (0.12, 0.81),
    "pointer-move": (0.19, 0.06),
    "question_arrow": (0.12, 0.31),
    "right_ptr": (0.75, 0.06),
    "right_side": (0.88, 0.50),
    "right_tee": (0.06, 0.50),
    "sb_down_arrow": (0.50, 0.81),
    "sb_left_arrow": (0.12, 0.50),
    "sb_right_arrow": (0.81, 0.50),
    "sb_up_arrow": (0.50, 0.12),
    "top_left_corner": (0.06, 0.06),
    "top_right_corner": (0.88, 0.06),
    "top_side": (0.50, 0.06),
    "top_tee": (0.50, 0.06),
    "ul_angle": (0.12, 0.12),
    "ur_angle": (0.88, 0.12),
    "zoom-in": (0.44, 0.44),
    "zoom-out": (0.44, 0.44),
}

with open("build.toml", "rb") as f_toml:
    config = tomllib.load(f_toml)

cursors = config["cursors"]
fallback = cursors["fallback_settings"]
default_x = fallback.get("x_hotspot", 128)
default_y = fallback.get("y_hotspot", 128)

bitmaps_dir = "bitmaps/Bibata-Modern-Ice"
os.makedirs(bitmaps_dir, exist_ok=True)

out_dir = "hyprcursor-build/theme_Bibata-Modern-Ice"
hyprcursors_dir = os.path.join(out_dir, "hyprcursors")
os.makedirs(hyprcursors_dir, exist_ok=True)

for key, cursor in cursors.items():
    if key == "fallback_settings":
        continue

    png_pattern = cursor["png"]
    svgs = []
    if "*" in png_pattern:
        base_name = png_pattern.split("-*")[0]
        svgs = sorted(
            glob.glob(os.path.join("svg/modern", base_name, "*.svg"))
        )
    else:
        base_name = png_pattern.replace(".png", ".svg")
        svg_path = os.path.join("svg/modern", base_name)
        if os.path.exists(svg_path):
            svgs = [svg_path]

    if "x11_name" in cursor:
        x11_name = cursor["x11_name"]
        hotspot_x, hotspot_y = hotspots.get(x11_name, (0.50, 0.50))
        shape_dir = os.path.join(hyprcursors_dir, x11_name)
        os.makedirs(shape_dir, exist_ok=True)

    for svg_path in svgs:
        name = os.path.basename(svg_path)
        png_name = name.replace(".svg", ".png")
        dst_png_path = os.path.join(bitmaps_dir, png_name)

        with open(svg_path, "r") as f_in:
            content = f_in.read()
        for match, replace in colors:
            content = content.replace(match, replace)

        if "x11_name" in cursor:
            dst_svg_path = os.path.join(shape_dir, name)
            with open(dst_svg_path, "w") as f_out:
                f_out.write(content)
            os.system(f"resvg -w 256 -h 256 {dst_svg_path} {dst_png_path}")
        else:
            tmp_svg_path = os.path.join(bitmaps_dir, name)
            with open(tmp_svg_path, "w") as f_out:
                f_out.write(content)
            os.system(f"resvg -w 256 -h 256 {tmp_svg_path} {dst_png_path}")
            os.remove(tmp_svg_path)

    if "x11_name" in cursor:
        meta_path = os.path.join(shape_dir, "meta.hl")
        meta_content = "resize_algorithm = none\n"
        meta_content += f"hotspot_x = {hotspot_x:.2f}\n"
        meta_content += f"hotspot_y = {hotspot_y:.2f}\n\n"

        for svg_path in svgs:
            name = os.path.basename(svg_path)
            meta_content += f"define_size = 0, {name}\n"

        for symlink in cursor.get("x11_symlinks", []):
            meta_content += f"define_override = {symlink}\n"

        meta_content += "\n"

        with open(meta_path, "w") as f_meta:
            f_meta.write(meta_content)

manifest_path = os.path.join(out_dir, "manifest.hl")
manifest_content = (
    "name = Bibata-Modern\n"
    "description = Custom Black and Blue Bibata cursors\n"
    "version = 0.1\n"
    "cursors_directory = hyprcursors\n"
)
with open(manifest_path, "w") as f_manifest:
    f_manifest.write(manifest_content)
