import json
import sys
import os


def resolve_target(lock_data, input_val):
    """Recursively resolve the node ID for a given input."""
    if isinstance(input_val, str):
        return input_val
    if isinstance(input_val, list):
        current_node_id = "root"
        for key in input_val:
            node = lock_data["nodes"].get(current_node_id)
            if not node:
                return None
            next_val = node.get("inputs", {}).get(key)
            if not next_val:
                return None
            current_node_id = resolve_target(lock_data, next_val)
        return current_node_id
    return None


def find_paths_to_nodes(lock_data):
    """BFS to find the shortest dependency paths to every node."""
    paths = {"root": [[]]}
    queue = ["root"]
    visited = {"root"}
    nodes = lock_data.get("nodes", {})

    while queue:
        current = queue.pop(0)
        for in_key, in_val in nodes.get(current, {}).get("inputs", {}).items():
            target_node = resolve_target(lock_data, in_val)
            if not target_node:
                continue
            if target_node not in paths:
                paths[target_node] = []

            for p in paths[current]:
                new_path = p + [in_key]
                existing = paths[target_node]
                if not existing or len(new_path) == len(existing[0]):
                    if new_path not in existing:
                        existing.append(new_path)
                elif len(new_path) < len(existing[0]):
                    paths[target_node] = [new_path]

            if target_node not in visited:
                visited.add(target_node)
                queue.append(target_node)
    return paths


def get_fixes(lock):
    """Logic to identify sub-inputs that don't follow top-level inputs."""
    nodes = lock.get("nodes", {})
    root_inputs = nodes.get("root", {}).get("inputs", {})
    top_targets = {k: resolve_target(lock, v) for k, v in root_inputs.items()}
    paths_to_nodes = find_paths_to_nodes(lock)
    fixes = set()

    for node_id, node_data in nodes.items():
        if node_id == "root":
            continue
        for in_key, in_val in node_data.get("inputs", {}).items():
            if in_key in top_targets:
                target_id = resolve_target(lock, in_val)
                if target_id and target_id != top_targets[in_key]:
                    for p in paths_to_nodes.get(node_id, []):
                        if p:
                            path = ".inputs.".join(p)
                            # Implicit string concatenation fixes line length
                            fixes.add(
                                f"inputs.{path}.inputs.{in_key}"
                                f'.follows = "{in_key}";'
                            )
    return fixes


def main():
    if not os.path.exists("flake.lock"):
        print("Error: flake.lock not found.")
        sys.exit(1)

    with open("flake.lock", encoding="utf-8") as f:
        lock = json.load(f)

    fixes = get_fixes(lock)

    if fixes:
        msg = (
            "Found missed follows! Add these directly inside "
            "your top-level `inputs = { ... };` block:\n"
        )
        print(msg)
        for fix in sorted(fixes):
            print(f"    {fix}")
    else:
        print("All dependencies are following top-level inputs correctly!")


if __name__ == "__main__":
    main()
