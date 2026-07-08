import sys
import os
import json

# Arguments:
# 1. Path to base config (e.g. /run/sing-box/merged.json)
# 2. Path to credential config.json (or "none" if not exists)
# 3. Path to output config.json (e.g. /run/sing-box/config.json)
# 4. JSON string of generated AWG outbounds (e.g. '[{"tag": "awg0", ...}]')
# 5. JSON string of dynamic tags to prepend (e.g. '["proxy-server", "awg0"]')

if len(sys.argv) < 6:
    print("Error: Missing arguments for build-config.py", file=sys.stderr)
    sys.exit(1)

base_config_path = sys.argv[1]
credential_config_path = sys.argv[2]
output_config_path = sys.argv[3]
awg_outbounds_str = sys.argv[4]
prepend_tags_str = sys.argv[5]

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
    awg_outbounds = (
        json.loads(awg_outbounds_str) if awg_outbounds_str.strip() else []
    )
except Exception as e:
    print(
        f"Warning: Failed to parse AWG outbounds JSON: {e}. Using empty list.",
        file=sys.stderr,
    )
    awg_outbounds = []

try:
    prepend_tags = (
        json.loads(prepend_tags_str) if prepend_tags_str.strip() else []
    )
except Exception as e:
    print(
        f"Warning: Failed to parse prepend tags JSON: {e}. Using empty list.",
        file=sys.stderr,
    )
    prepend_tags = []


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


# 1. Merge with credential config if it exists
if (
    credential_config_path
    and credential_config_path.lower() != "none"
    and os.path.isfile(credential_config_path)
):
    try:
        with open(credential_config_path, "r") as f:
            cred_config = json.load(f)
        deep_merge(config, cred_config)
    except Exception as e:
        print(
            f"Warning: Failed to read or merge {credential_config_path}: {e}",
            file=sys.stderr,
        )

# 2. Append AWG outbounds to outbounds list
if "outbounds" not in config or not isinstance(config["outbounds"], list):
    config["outbounds"] = []
config["outbounds"].extend(awg_outbounds)

# 3. Process the "out" or "proxy" selector to prepend tags and deduplicate
for outbound in config.get("outbounds", []):
    if (
        isinstance(outbound, dict)
        and outbound.get("tag") in ("out", "proxy")
        and outbound.get("type") == "selector"
    ):
        existing_list = outbound.get("outbounds", [])
        if not isinstance(existing_list, list):
            existing_list = []

        # Build combined list (new tags first, then existing tags)
        combined = prepend_tags + existing_list

        # Deduplicate while preserving first-seen order
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
