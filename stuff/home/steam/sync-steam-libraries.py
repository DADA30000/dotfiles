#!/usr/bin/env python3
import os
import re
import sys

def main():
    extra_libs = sys.argv[1:]
    if not extra_libs:
        return

    home = os.path.expanduser("~")
    vdf_paths = [
        f"{home}/.nixpak/com.valvesoftware.Steam/home/.local/share/Steam/config/libraryfolders.vdf",
        f"{home}/.nixpak/com.valvesoftware.Steam/home/.local/share/Steam/steamapps/libraryfolders.vdf",
    ]

    for vdf_path in vdf_paths:
        if not os.path.exists(vdf_path):
            continue
        try:
            with open(vdf_path, "r", encoding="utf-8") as f:
                content = f.read()

            user = os.environ.get("USER", "l0lk3k")
            # Replace transient doc portal paths with direct host paths
            content = re.sub(
                r"/run/user/\d+/doc/[^/]+/SteamLibrary",
                f"/mnt/data-nvme/{user}/SteamLibrary",
                content,
            )

            # Discover current highest index
            indices = [int(m) for m in re.findall(r'"(\d+)"\s*\{', content)]
            next_idx = max(indices, default=-1) + 1

            modified = False
            for lib_path in extra_libs:
                os.makedirs(lib_path, exist_ok=True)

                if lib_path not in content:
                    cid = "0"
                    meta = os.path.join(lib_path, "libraryfolder.vdf")
                    if os.path.exists(meta):
                        try:
                            with open(meta, "r", encoding="utf-8") as mf:
                                m = re.search(r'"contentid"\s*"(\d+)"', mf.read())
                                if m:
                                    cid = m.group(1)
                        except Exception:
                            pass

                    block = (
                        f'\t"{next_idx}"\n'
                        f'\t{{\n'
                        f'\t\t"path"\t\t"{lib_path}"\n'
                        f'\t\t"label"\t\t""\n'
                        f'\t\t"contentid"\t\t"{cid}"\n'
                        f'\t\t"totalsize"\t\t"0"\n'
                        f'\t\t"update_clean_bytes_tally"\t\t"0"\n'
                        f'\t\t"time_last_update_verified"\t\t"0"\n'
                        f'\t\t"apps"\n'
                        f'\t\t{{\n'
                        f'\t\t}}\n'
                        f'\t}}\n'
                        f'}}'
                    )
                    content = content.rstrip().rstrip("}").rstrip() + "\n" + block + "\n"
                    next_idx += 1
                    modified = True

            with open(vdf_path, "w", encoding="utf-8") as f:
                f.write(content)
        except Exception as e:
            sys.stderr.write(f"[sync-steam-libraries] Error updating {vdf_path}: {e}\n")

if __name__ == "__main__":
    main()
