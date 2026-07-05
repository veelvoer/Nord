#!/usr/bin/env python3
"""Parse hyprland.lua to extract hl.bind() calls as JSON.

Output: array of { key, dispatcher, flags }
Key is the hl.bind key string (e.g. "SUPER + Q").
Dispatcher is the Lua expression for the second arg (e.g. hl.dsp.exec_cmd("kitty")).
Flags is the optional third arg string (e.g. { locked = true }) or null.
"""

import json
import re
import sys


def parse_hyprland_lua(filepath):
    with open(filepath) as f:
        source = f.read()

    lines = source.split("\n")

    # --- 1. Extract variable assignments ---
    variables = {}
    for line in lines:
        stripped = line.strip()
        # local varname = "string"
        m = re.match(r'local\s+(\w+)\s*=\s*"([^"]*)"', stripped)
        if m:
            variables[m.group(1)] = m.group(2)
            continue
        # local varname = "string" .. "string"
        m = re.match(r'local\s+(\w+)\s*=\s*"([^"]*)"\s*\.\.\s*"([^"]*)"', stripped)
        if m:
            variables[m.group(1)] = m.group(2) + m.group(3)
            continue

    # --- 2. Find and expand the for loop (workspace binds) ---
    for_start = None
    for_end = None
    brace_depth = 0
    for i, line in enumerate(lines):
        stripped = line.strip()
        if re.match(r'for\s+\w+\s*=\s*\d+,\s*\d+\s+do', stripped):
            for_start = i
            brace_depth = 0
        if for_start is not None and i >= for_start:
            brace_depth += stripped.count("do") + stripped.count("then") - stripped.count("end")
            if "end" in stripped and (brace_depth <= 0 or i == for_start + 1):
                for_end = i
                break

    # Expand for loop manually - the body has two hl.bind calls per iteration
    loop_bindings = []
    if for_start is not None and for_end is not None:
        mod = variables.get("mainMod", "SUPER")
        for i in range(1, 11):
            key_num = i % 10  # 10 maps to key 0
            # hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
            loop_bindings.append({
                "key": f"{mod} + {key_num}",
                "dispatcher": f"hl.dsp.focus({{ workspace = {i} }})",
                "flags": None,
            })
            # hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
            loop_bindings.append({
                "key": f"{mod} + SHIFT + {key_num}",
                "dispatcher": f"hl.dsp.window.move({{ workspace = {i} }})",
                "flags": None,
            })

    # --- 3. Extract all hl.bind() calls from the full source ---
    # Remove the for loop section to avoid double-processing
    all_bindings = loop_bindings
    if for_start is not None and for_end is not None:
        # Process before and after the for loop
        sections = []
        if for_start > 0:
            sections.append("\n".join(lines[:for_start]))
        if for_end < len(lines) - 1:
            sections.append("\n".join(lines[for_end + 1:]))
        for section in sections:
            for b in _extract_binds_from_text(section, variables):
                all_bindings.append(b)
    else:
        for b in _extract_binds_from_text(source, variables):
            all_bindings.append(b)

    return all_bindings


def _extract_binds_from_text(text, variables):
    """Extract hl.bind() calls from Lua text, resolving variables."""
    results = []
    # Match hl.bind( ... ) possibly spanning multiple lines
    # We need to handle nested parens
    pos = 0
    while True:
        idx = text.find("hl.bind(", pos)
        if idx == -1:
            break
        # Find matching closing paren
        start = idx + len("hl.bind(")
        depth = 1
        i = start
        while i < len(text) and depth > 0:
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
            elif text[i] == '"':
                # Skip string
                i += 1
                while i < len(text) and text[i] != '"':
                    if text[i] == "\\":
                        i += 1  # skip escaped char
                    i += 1
            elif text[i] == "'":
                i += 1
                while i < len(text) and text[i] != "'":
                    if text[i] == "\\":
                        i += 1
                    i += 1
            i += 1
        if depth != 0:
            pos = idx + 1
            continue
        call_content = text[start:i - 1].strip()
        pos = i

        # Skip if it's inside a comment
        line_start = text.rfind("\n", 0, idx) + 1
        line_text = text[line_start:idx].strip()
        if line_text.startswith("--"):
            continue

        # Split into args (respecting parens and strings)
        args = _split_args(call_content)

        if len(args) < 2:
            continue

        # --- Parse key arg (first arg) ---
        key_expr = args[0].strip()
        key_string = _resolve_string_expr(key_expr, variables)
        if key_string is None:
            continue

        # --- Parse dispatcher arg (second arg) ---
        dispatcher = args[1].strip()
        dispatcher = _resolve_dispatcher(dispatcher, variables)

        # --- Parse flags arg (third arg, optional) ---
        flags = None
        if len(args) >= 3:
            flags = args[2].strip()

        results.append({
            "key": key_string,
            "dispatcher": dispatcher,
            "flags": flags,
        })

    return results


def _split_args(text):
    """Split function arguments by top-level commas."""
    args = []
    paren_depth = 0
    brace_depth = 0
    current = []
    in_string = None
    i = 0
    while i < len(text):
        c = text[i]
        if in_string:
            current.append(c)
            if c == "\\" and i + 1 < len(text):
                current.append(text[i + 1])
                i += 2
                continue
            if c == in_string:
                in_string = None
        elif c in ('"', "'"):
            in_string = c
            current.append(c)
        elif c == "{":
            brace_depth += 1
            current.append(c)
        elif c == "}":
            brace_depth -= 1
            current.append(c)
        elif c == "(":
            paren_depth += 1
            current.append(c)
        elif c == ")":
            paren_depth -= 1
            current.append(c)
        elif c == "," and paren_depth == 0 and brace_depth == 0:
            args.append("".join(current).strip())
            current = []
        else:
            current.append(c)
        i += 1
    if current:
        args.append("".join(current).strip())
    return args


def _resolve_string_expr(expr, variables):
    """Resolve a Lua string expression like mainMod .. " + Q" or just "foo"."""
    expr = expr.strip()

    # Simple quoted string
    m = re.match(r'^"([^"]*)"$', expr)
    if m:
        return m.group(1)

    # Concatenation: a .. b .. c
    parts = re.split(r'\s*\.\.\s*', expr)
    result = ""
    for part in parts:
        part = part.strip()
        m = re.match(r'^"([^"]*)"$', part)
        if m:
            result += m.group(1)
        elif part in variables:
            result += variables[part]
        else:
            return None  # can't resolve
    return result


def _resolve_dispatcher(expr, variables):
    """Resolve variable references inside a dispatcher expression."""
    expr = expr.strip()
    # Replace known variables with their string values
    for varname, varval in variables.items():
        # Replace variable references but not inside strings
        # Simple approach: just replace whole-word occurrences
        expr = re.sub(r'\b' + re.escape(varname) + r'\b', f'"{varval}"', expr)
    return expr


if __name__ == "__main__":
    filepath = sys.argv[1] if len(sys.argv) > 1 else "~/.config/hypr/hyprland.lua"
    filepath = filepath.replace("~", __import__("os").path.expanduser("~"))
    bindings = parse_hyprland_lua(filepath)
    json.dump(bindings, sys.stdout, indent=2)
