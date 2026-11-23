#!/usr/bin/env python3

import zipfile
import json
import uuid
import os
import sys
import argparse


def extract_json_from_xpi(xpi_path, json_entry_path):
    """
    Reads and parses a JSON file from within an XPI archive.
    Returns None if the file is not found.
    """
    try:
        with zipfile.ZipFile(xpi_path, "r") as zf:
            with zf.open(json_entry_path) as f:
                return json.loads(f.read().decode("utf-8"))
    except KeyError:
        return None
    except Exception as e:
        print(
            f"Error extracting {json_entry_path} from {xpi_path}: {e}",
            file=sys.stderr,
        )
        return None


def resolve_message(message_key, messages_data, default_value):
    """
    Resolves a __MSG_key__ placeholder using messages_data.
    """
    if (
        message_key
        and message_key.startswith("__MSG_")
        and message_key.endswith("__")
    ):
        key_name = message_key[len("__MSG_") : -len("__")]
        if (
            messages_data
            and key_name in messages_data
            and "message" in messages_data[key_name]
        ):
            return messages_data[key_name]["message"]
    return default_value


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Generate a deterministic extensions.json file for Firefox."
        ),
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "--profile-path",
        help=(
            "The absolute path to the target Firefox profile directory"
            " (e.g., ~/.config/zen/default)"
        ),
        required=True,
    )
    parser.add_argument(
        "--extension",
        action="append",
        dest="extensions",
        help=(
            "Path to a source XPI file, with an optional ID override "
            "separated by a colon.\n"
            "Repeat this argument for each extension.\n"
            "Example:\n"
            "  --extension /path/to/ryd.xpi:return-youtube-dislike@jetbra.in\n"
            "  --extension /path/to/darkreader.xpi\n"
        ),
        required=True,
    )
    args = parser.parse_args()

    addons_data = []

    for ext_arg in args.extensions:
        parts = ext_arg.split(":", 1)
        if len(parts) == 2:
            xpi_file, id_override = parts
        else:
            xpi_file, id_override = parts[0], None

        if not os.path.exists(xpi_file):
            print(f"File not found: {xpi_file}", file=sys.stderr)
            continue

        print(f"Processing {xpi_file}...")

        manifest = extract_json_from_xpi(xpi_file, "manifest.json")
        if not manifest:
            print(
                f"Skipping {xpi_file}: manifest.json not found or invalid.",
                file=sys.stderr,
            )
            continue

        gecko_settings = manifest.get("browser_specific_settings", {}).get(
            "gecko", {}
        )

        addon_id = id_override
        if not addon_id:
            addon_id = gecko_settings.get("id") or manifest.get(
                "applications", {}
            ).get("gecko", {}).get("id")
        if not addon_id:
            filename = os.path.splitext(os.path.basename(xpi_file))[0]
            addon_id = f"{filename}@example.com"
            warning_msg = (
                f"Warning: No ID found for {xpi_file}. "
                f"Using generated ID: {addon_id}"
            )
            print(warning_msg, file=sys.stderr)

        # --- Path Generation ---
        profile_path = os.path.expanduser(args.profile_path)
        xpi_filename = os.path.basename(xpi_file)
        target_addon_path = os.path.join(
            profile_path, "extensions", xpi_filename
        )
        root_uri = f"jar:file://{target_addon_path}!/"

        version = manifest.get("version", "unknown")
        name_from_manifest = manifest.get("name", "Unnamed Addon")
        description_from_manifest = manifest.get(
            "description", "No description available."
        )
        manifest_version = manifest.get("manifest_version", 2)
        author = (
            manifest.get("author") or manifest.get("developer") or "Unknown"
        )
        default_locale_code = manifest.get("default_locale", "en")
        icons = manifest.get("icons", {})

        min_version = gecko_settings.get("strict_min_version", "42.0")
        target_applications = [
            {
                "id": "toolkit@mozilla.org",
                "minVersion": min_version,
                "maxVersion": "*",
            }
        ]

        namespace = uuid.UUID("00000000-0000-0000-0000-000000000000")
        sync_guid = str(uuid.uuid5(namespace, addon_id))
        install_date, update_date, signed_date = 1000, 1000, 1000

        locales_list = []
        try:
            with zipfile.ZipFile(xpi_file, "r") as zf:
                messages_paths = [
                    name
                    for name in zf.namelist()
                    if name.startswith("_locales/")
                    and name.endswith("/messages.json")
                ]
                for msg_path in messages_paths:
                    locale_code = msg_path.split("/")[1]
                    messages_data = extract_json_from_xpi(xpi_file, msg_path)
                    locale_name = resolve_message(
                        name_from_manifest, messages_data, name_from_manifest
                    )
                    locale_description = resolve_message(
                        description_from_manifest,
                        messages_data,
                        description_from_manifest,
                    )
                    locales_list.append(
                        {
                            "name": locale_name,
                            "description": locale_description,
                            "creator": author,
                            "developers": None,
                            "translators": None,
                            "contributors": None,
                            "locales": [locale_code],
                        }
                    )
        except Exception as e:
            print(
                f"Warning: Could not process locales for {xpi_file}: {e}",
                file=sys.stderr,
            )

        default_locale_messages = extract_json_from_xpi(
            xpi_file, f"_locales/{default_locale_code}/messages.json"
        )
        if default_locale_messages:
            name_from_manifest = resolve_message(
                name_from_manifest, default_locale_messages, name_from_manifest
            )
            description_from_manifest = resolve_message(
                description_from_manifest,
                default_locale_messages,
                description_from_manifest,
            )

        addon_entry = {
            "id": addon_id,
            "syncGUID": "{" + sync_guid + "}",
            "version": version,
            "type": "extension",
            "loader": None,
            "updateURL": None,
            "installOrigins": None,
            "manifestVersion": manifest_version,
            "optionsURL": None,
            "optionsType": None,
            "optionsBrowserStyle": True,
            "aboutURL": None,
            "defaultLocale": {
                "name": name_from_manifest,
                "description": description_from_manifest,
                "creator": author,
                "developers": None,
                "translators": None,
                "contributors": None,
            },
            "visible": True,
            "active": True,
            "userDisabled": False,
            "appDisabled": False,
            "embedderDisabled": False,
            "installDate": install_date,
            "updateDate": update_date,
            "applyBackgroundUpdates": 1,
            "path": target_addon_path,
            "skinnable": False,
            "sourceURI": None,
            "releaseNotesURI": None,
            "softDisabled": False,
            "foreignInstall": True,
            "strictCompatibility": True,
            "locales": locales_list,
            "targetApplications": target_applications,
            "targetPlatforms": [],
            "signedState": 2,
            "signedTypes": [2, 1],
            "signedDate": signed_date,
            "seen": True,
            "dependencies": [],
            "incognito": "spanning",
            "userPermissions": {"permissions": [], "origins": []},
            "optionalPermissions": {"permissions": [], "origins": []},
            "requestedPermissions": {"permissions": [], "origins": []},
            "icons": icons,
            "iconURL": None,
            "blocklistAttentionDismissed": False,
            "blocklistState": 0,
            "blocklistURL": None,
            "startupData": None,
            "hidden": False,
            "installTelemetryInfo": None,
            "recommendationState": None,
            "rootURI": root_uri,
            "location": "app-profile",
        }
        addons_data.append(addon_entry)

    final_json = {"schemaVersion": 37, "addons": addons_data}

    with open("generated_extensions.json", "w", encoding="utf-8") as f:
        json.dump(final_json, f, indent=2, ensure_ascii=False)

    print("\nSuccessfully generated generated_extensions.json")


if __name__ == "__main__":
    main()
