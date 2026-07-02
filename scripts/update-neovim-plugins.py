#!/usr/bin/env python3
"""
Neovim plugin auto-update helper script.

Usage:
    python3 update-neovim-plugins.py parse FILENAME
    python3 update-neovim-plugins.py update FILENAME PLUGIN_NAME NEW_REV NEW_SHA256
"""

import json
import re
import sys
import os


def parse_plugins(filename):
    """Parse the plugins.nix file and extract all plugin definitions."""
    with open(filename, 'r') as f:
        content = f.read()
    
    # Find the customPlugins list
    # We need to extract the content between the square brackets
    custom_plugins_match = re.search(
        r'customPlugins\s*=\s*\[([^\]]*)\]\s*;',
        content,
        re.DOTALL
    )
    
    if not custom_plugins_match:
        print("ERROR: Could not find customPlugins list in file", file=sys.stderr)
        sys.exit(1)
    
    custom_plugins_str = custom_plugins_match.group(1)
    
    # Find all plugin blocks - single level braces only
    # This regex matches individual plugin objects in the list
    plugin_pattern = re.compile(
        r'\{[^{}]*?name\s*=\s*"([^"]+)"[^{}]*?\}',
        re.DOTALL
    )
    
    plugins = []
    for match in plugin_pattern.finditer(custom_plugins_str):
        plugin_block = match.group(0)
        
        # Extract individual fields
        name_match = re.search(r'name\s*=\s*"([^"]+)"', plugin_block)
        owner_match = re.search(r'owner\s*=\s*"([^"]+)"', plugin_block)
        repo_match = re.search(r'repo\s*=\s*"([^"]+)"', plugin_block)
        rev_match = re.search(r'rev\s*=\s*"([^"]+)"', plugin_block)
        sha256_match = re.search(r'sha256\s*=\s*"([^"]+)"', plugin_block)
        
        if not all([name_match, owner_match, repo_match, rev_match, sha256_match]):
            print(f"ERROR: Malformed plugin block: {plugin_block[:100]}...", file=sys.stderr)
            sys.exit(1)
        
        plugin = {
            'name': name_match.group(1),
            'owner': owner_match.group(1),
            'repo': repo_match.group(1),
            'rev': rev_match.group(1),
            'sha256': sha256_match.group(1)
        }
        plugins.append(plugin)
    
    return plugins


def find_plugin_block(content, plugin_name):
    """Find a single plugin block by name, return the full block string."""
    # Match single-level braces containing the plugin name
    pattern = re.compile(
        r'\{[^{}]*?name\s*=\s*"' + re.escape(plugin_name) + r'"[^{}]*?\}',
        re.DOTALL
    )
    
    matches = pattern.findall(content)
    
    if len(matches) == 0:
        print(f"ERROR: Plugin '{plugin_name}' not found", file=sys.stderr)
        sys.exit(1)
    elif len(matches) > 1:
        print(f"ERROR: Multiple matches found for plugin '{plugin_name}'", file=sys.stderr)
        sys.exit(1)
    
    return matches[0]


def cmd_parse():
    """Handle the parse subcommand."""
    if len(sys.argv) < 3:
        print("Usage: python3 update-neovim-plugins.py parse FILENAME", file=sys.stderr)
        sys.exit(1)
    
    filename = sys.argv[2]
    
    if not os.path.exists(filename):
        print(f"ERROR: File '{filename}' not found", file=sys.stderr)
        sys.exit(1)
    
    plugins = parse_plugins(filename)
    
    # Critical: must have exactly 7 plugins
    if len(plugins) < 7:
        print(f"ERROR: Expected at least 7 plugins, found {len(plugins)}", file=sys.stderr)
        print("This indicates a structural change in plugins.nix", file=sys.stderr)
        sys.exit(1)
    
    # Output as JSON array
    print(json.dumps(plugins))


def cmd_update():
    """Handle the update subcommand."""
    if len(sys.argv) < 6:
        print("Usage: python3 update-neovim-plugins.py update FILENAME PLUGIN_NAME NEW_REV NEW_SHA256", file=sys.stderr)
        sys.exit(1)
    
    filename = sys.argv[2]
    plugin_name = sys.argv[3]
    new_rev = sys.argv[4]
    new_sha256 = sys.argv[5]
    
    if not os.path.exists(filename):
        print(f"ERROR: File '{filename}' not found", file=sys.stderr)
        sys.exit(1)
    
    # Step 1: Parse the file to get plugin count
    with open(filename, 'r') as f:
        content = f.read()
    
    plugins_before = parse_plugins(filename)
    plugin_count_before = len(plugins_before)
    
    # Step 2: Find the plugin block
    plugin_block = find_plugin_block(content, plugin_name)
    
    # Step 3: Substitute rev
    rev_pattern = re.compile(r'rev\s*=\s*"([^"]+)"')
    new_block, rev_sub_count = rev_pattern.subn(f'rev = "{new_rev}"', plugin_block, count=1)
    
    if rev_sub_count != 1:
        print(f"ERROR: rev substitution failed for plugin '{plugin_name}' (count: {rev_sub_count})", file=sys.stderr)
        sys.exit(1)
    
    # Step 4: Substitute sha256
    sha256_pattern = re.compile(r'sha256\s*=\s*"([^"]+)"')
    new_block, sha256_sub_count = sha256_pattern.subn(f'sha256 = "{new_sha256}"', new_block, count=1)
    
    if sha256_sub_count != 1:
        print(f"ERROR: sha256 substitution failed for plugin '{plugin_name}' (count: {sha256_sub_count})", file=sys.stderr)
        sys.exit(1)
    
    # Step 5: Replace the block in the full content
    updated_content = content.replace(plugin_block, new_block)
    
    # Step 6: Write back to file
    with open(filename, 'w') as f:
        f.write(updated_content)
    
    # Step 7: Re-parse to validate
    plugins_after = parse_plugins(filename)
    plugin_count_after = len(plugins_after)
    
    if plugin_count_after != plugin_count_before:
        print(f"ERROR: Plugin count changed from {plugin_count_before} to {plugin_count_after}", file=sys.stderr)
        sys.exit(1)
    
    # Find the updated plugin and verify its values
    updated_plugin = None
    for p in plugins_after:
        if p['name'] == plugin_name:
            updated_plugin = p
            break
    
    if updated_plugin is None:
        print(f"ERROR: Updated plugin '{plugin_name}' not found after update", file=sys.stderr)
        sys.exit(1)
    
    if updated_plugin['rev'] != new_rev:
        print(f"ERROR: Plugin '{plugin_name}' rev mismatch: expected '{new_rev}', got '{updated_plugin['rev']}'", file=sys.stderr)
        sys.exit(1)
    
    if updated_plugin['sha256'] != new_sha256:
        print(f"ERROR: Plugin '{plugin_name}' sha256 mismatch: expected '{new_sha256}', got '{updated_plugin['sha256']}'", file=sys.stderr)
        sys.exit(1)
    
    # Success
    print(f"Updated {plugin_name}: {new_rev} {new_sha256}")


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Usage: python3 update-neovim-plugins.py <parse|update> [args...]", file=sys.stderr)
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == 'parse':
        cmd_parse()
    elif command == 'update':
        cmd_update()
    else:
        print(f"ERROR: Unknown command '{command}'", file=sys.stderr)
        print("Available commands: parse, update", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()