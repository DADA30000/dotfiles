import json
import os
import sys

# Arguments:
# 1. Base config (e.g. sing-box-config-file)
# 2. Output config (e.g. /run/sing-box/config.json)
# 3. JSON string of generated AWG outbounds (e.g. '[]')
# 4+. Extra config file paths (e.g. sub_config.json, config.json)

if len(sys.argv) < 3:
    print("Error: Missing arguments", file=sys.stderr)
    sys.exit(1)

base_config_path = sys.argv[1]
output_config_path = sys.argv[2]
awg_outbounds_str = sys.argv[3] if len(sys.argv) > 3 else "[]"
extra_config_paths = sys.argv[4:]

# Load base config
try:
    with open(base_config_path, "r") as f:
        config = json.load(f)
except Exception as e:
    print(
        f"Error: Failed to load base config from {base_config_path}: {e}",
        file=sys.stderr,
    )
    sys.exit(1)

# Parse dynamic inputs safely
try:
    if awg_outbounds_str.strip():
        awg_outbounds = json.loads(awg_outbounds_str)
    else:
        awg_outbounds = []
except Exception as e:
    print(
        f"Warning: Failed to parse AWG outbounds JSON: {e}.",
        file=sys.stderr,
    )
    awg_outbounds = []


# Deep merge function
def deep_merge(dict1, dict2):
    for key, val2 in dict2.items():
        if key in dict1:
            val1 = dict1[key]
            if isinstance(val1, dict) and isinstance(val2, dict):
                deep_merge(val1, val2)
            elif isinstance(val1, list) and isinstance(val2, list):
                dict1[key] = val1 + val2
            else:
                dict1[key] = val2
        else:
            dict1[key] = val2


def extract_tags(cfg):
    tags = []
    for item in cfg.get("outbounds", []):
        if isinstance(item, dict) and item.get("tag"):
            tags.append(item["tag"])
    for item in cfg.get("endpoints", []):
        if isinstance(item, dict) and item.get("tag"):
            tags.append(item["tag"])
    return tags


# Merge each extra config in order
loaded_extra_configs = []
for path in extra_config_paths:
    if not path or path.lower() == "none" or not os.path.isfile(path):
        continue
    try:
        with open(path, "r") as f:
            extra_cfg = json.load(f)
        deep_merge(config, extra_cfg)
        loaded_extra_configs.append(extra_cfg)
    except Exception as e:
        print(
            f"Warning: Failed to read or merge {path}: {e}",
            file=sys.stderr,
        )

# Append AWG outbounds to outbounds list
if "outbounds" not in config or not isinstance(config["outbounds"], list):
    config["outbounds"] = []
config["outbounds"].extend(awg_outbounds)

# Collect tags from extra configs (config.json tags before sub tags)
prepend_tags = []
for extra_cfg in reversed(loaded_extra_configs):
    prepend_tags.extend(extract_tags(extra_cfg))

# Process the "out" or "proxy" selector to prepend tags and deduplicate
for outbound in config.get("outbounds", []):
    if (
        isinstance(outbound, dict)
        and outbound.get("tag") in ("out", "proxy")
        and outbound.get("type") == "selector"
    ):
        existing_list = outbound.get("outbounds", [])
        if not isinstance(existing_list, list):
            existing_list = []

        combined = prepend_tags + existing_list

        seen = set()
        deduped = []
        for tag in combined:
            if tag and isinstance(tag, str) and tag not in seen:
                seen.add(tag)
                deduped.append(tag)

        outbound["outbounds"] = deduped

# Save the final config
try:
    with open(output_config_path, "w") as f:
        json.dump(config, f, indent=2)
except Exception as e:
    print(
        f"Error: Failed to write output config to {output_config_path}: {e}",
        file=sys.stderr,
    )
    sys.exit(1)

print("Configuration built successfully.")
