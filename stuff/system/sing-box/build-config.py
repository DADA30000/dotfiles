import json
import os
import sys

# Arguments:
# [--sfa]
# 1. Base config (e.g. sing-box-config-file)
# 2. Output config (e.g. /run/sing-box/config.json)
# 3+. Extra config file paths (e.g. sub_config.json, config.json)

argv = sys.argv[1:]
sfa_mode = False
if argv and argv[0] == "--sfa":
    sfa_mode = True
    argv = argv[1:]

if len(argv) < 2:
    print("Error: Missing arguments", file=sys.stderr)
    sys.exit(1)

base_config_path = argv[0]
output_config_path = argv[1]
extra_config_paths = argv[2:]

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


def is_host_only_outbound(item):
    if not isinstance(item, dict):
        return False
    for key in (
        "bind_interface",
        "inet4_bind_address",
        "inet6_bind_address",
        "routing_mark",
    ):
        if item.get(key):
            return True
    server = item.get("server")
    if isinstance(server, str) and server in ("127.0.0.1", "::1", "localhost"):
        return True
    return False


def adapt_for_sfa(extra_cfg):
    adapted = dict(extra_cfg)
    adapted.pop("route", None)
    removed_tags = set()

    if isinstance(adapted.get("outbounds"), list):
        kept = []
        for item in adapted["outbounds"]:
            if is_host_only_outbound(item):
                tag = item.get("tag")
                if tag:
                    removed_tags.add(tag)
                continue
            kept.append(item)
        adapted["outbounds"] = kept

    if isinstance(adapted.get("endpoints"), list):
        kept_endpoints = []
        for ep in adapted["endpoints"]:
            if not isinstance(ep, dict):
                kept_endpoints.append(ep)
                continue
            ep = dict(ep)
            if ep.get("type") == "wireguard":
                # SFA uses userspace WireGuard/AmneziaWG (no kernel wg0)
                ep.pop("system", None)
                ep.pop("name", None)
                ep.pop("bind_interface", None)
            elif ep.get("bind_interface"):
                tag = ep.get("tag")
                if tag:
                    removed_tags.add(tag)
                continue
            kept_endpoints.append(ep)
        adapted["endpoints"] = kept_endpoints

    return adapted, removed_tags


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
all_removed_tags = set()
for path in extra_config_paths:
    if not path or path.lower() == "none" or not os.path.isfile(path):
        continue
    try:
        with open(path, "r") as f:
            extra_cfg = json.load(f)
        if sfa_mode:
            extra_cfg, removed = adapt_for_sfa(extra_cfg)
            all_removed_tags.update(removed)
        deep_merge(config, extra_cfg)
        loaded_extra_configs.append(extra_cfg)
    except Exception as e:
        print(
            f"Warning: Failed to read or merge {path}: {e}",
            file=sys.stderr,
        )

if "outbounds" not in config or not isinstance(config["outbounds"], list):
    config["outbounds"] = []

if sfa_mode:
    for inbound in config.get("inbounds", []):
        if isinstance(inbound, dict) and inbound.get("type") == "tun":
            inbound.pop("interface_name", None)

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
            if (
                tag
                and isinstance(tag, str)
                and tag not in seen
                and tag not in all_removed_tags
            ):
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
