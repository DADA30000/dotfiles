import os
import sys

for path in sys.argv[1:]:
    if not os.path.exists(path):
        continue
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        s = f.read()

    if "import filecmp" not in s:
        s = s.replace("#!/usr/bin/env python3\n", "#!/usr/bin/env python3\nimport filecmp\n", 1)

    old_check = "        if file_exists(dst, follow_symlinks=False):\n            os.remove(dst)"
    new_check = (
        "        if file_exists(dst, follow_symlinks=False):\n"
        "            if os.path.isfile(dst) and os.path.isfile(src):\n"
        "                try:\n"
        "                    if os.path.samefile(src, dst) or (os.path.getsize(src) == os.path.getsize(dst) and filecmp.cmp(src, dst, shallow=False)):\n"
        "                        return\n"
        "                except OSError:\n"
        "                    pass\n"
        "            os.remove(dst)"
    )
    if old_check in s:
        s = s.replace(old_check, new_check, 1)

    old_file_check = "        if file_exists(dst, follow_symlinks=False):\n            os.remove(dst)\n        copyfile(src, dst)"
    new_file_check = (
        "        if file_exists(dst, follow_symlinks=False):\n"
        "            if os.path.isfile(dst) and os.path.isfile(src):\n"
        "                try:\n"
        "                    if os.path.samefile(src, dst) or (os.path.getsize(src) == os.path.getsize(dst) and filecmp.cmp(src, dst, shallow=False)):\n"
        "                        return\n"
        "                except OSError:\n"
        "                    pass\n"
        "            os.remove(dst)\n"
        "        copyfile(src, dst)"
    )
    if old_file_check in s:
        s = s.replace(old_file_check, new_file_check, 1)

    os.chmod(path, 0o755)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s)
    print("Successfully processed proton script:", path)
