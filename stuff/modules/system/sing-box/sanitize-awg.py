import sys

conf_path = sys.argv[1]
output_path = sys.argv[2]
fwmark = sys.argv[3]

with open(conf_path, "r") as f:
    lines = f.readlines()

new_lines = []
interface_block_found = False
table_set = False
fwmark_set = False

for line in lines:
    stripped = line.strip()
    # Keep comment tags like '# tag=' or other lines
    if not stripped:
        continue
    if stripped.startswith("#") and not stripped.startswith("# tag="):
        continue

    # Strip empty fields like "Field = " or "Address = "
    if "=" in stripped:
        key, val = stripped.split("=", 1)
        if not val.strip():
            continue

    if stripped.lower() == "[interface]":
        interface_block_found = True
        new_lines.append(line)
        continue

    if interface_block_found:
        # If we exit the Interface block, ensure Table & FwMark are written
        if stripped.startswith("[") and stripped.endswith("]"):
            if not table_set:
                new_lines.append("Table = off\n")
            if not fwmark_set:
                new_lines.append(f"FwMark = {fwmark}\n")
            interface_block_found = False
        else:
            if stripped.lower().startswith("table"):
                new_lines.append("Table = off\n")
                table_set = True
                continue
            if stripped.lower().startswith("fwmark"):
                new_lines.append(f"FwMark = {fwmark}\n")
                fwmark_set = True
                continue

    new_lines.append(line)

if interface_block_found:
    if not table_set:
        new_lines.append("Table = off\n")
    if not fwmark_set:
        new_lines.append(f"FwMark = {fwmark}\n")

with open(output_path, "w") as f:
    f.writelines(new_lines)
