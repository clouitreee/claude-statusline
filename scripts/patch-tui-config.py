#!/usr/bin/env python3
"""Add a local TUI plugin to OpenCode's tui.json while preserving JSONC comments."""

from __future__ import annotations

import json
import pathlib
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class Token:
    kind: str
    value: str
    start: int
    end: int


def tokens(source: str) -> list[Token]:
    out: list[Token] = []
    index = 0
    while index < len(source):
        char = source[index]
        if char.isspace():
            index += 1
            continue
        if source.startswith("//", index):
            newline = source.find("\n", index + 2)
            index = len(source) if newline == -1 else newline + 1
            continue
        if source.startswith("/*", index):
            end = source.find("*/", index + 2)
            if end == -1:
                raise ValueError("unterminated block comment")
            index = end + 2
            continue
        if char == '"':
            start = index
            index += 1
            escaped = False
            while index < len(source):
                current = source[index]
                index += 1
                if escaped:
                    escaped = False
                elif current == "\\":
                    escaped = True
                elif current == '"':
                    break
            else:
                raise ValueError("unterminated string")
            raw = source[start:index]
            out.append(Token("string", json.loads(raw), start, index))
            continue
        if char in "{}[]:,":
            out.append(Token(char, char, index, index + 1))
        index += 1
    return out


def root_plugin_array(source: str, parsed: dict[str, object]) -> tuple[int, int, bool, int] | None:
    stream = tokens(source)
    object_depth = 0
    array_depth = 0
    for position, token in enumerate(stream):
        if token.kind == "{":
            object_depth += 1
            continue
        if token.kind == "}":
            object_depth -= 1
            continue
        if token.kind == "[":
            array_depth += 1
            continue
        if token.kind == "]":
            array_depth -= 1
            continue
        if token.kind != "string" or token.value != "plugin" or object_depth != 1 or array_depth != 0:
            continue
        if position + 2 >= len(stream) or stream[position + 1].kind != ":" or stream[position + 2].kind != "[":
            raise ValueError('top-level "plugin" must be an array')
        opening = stream[position + 2]
        nesting = 1
        last_kind = ""
        last_end = opening.end
        for following in stream[position + 3 :]:
            if following.kind == "[":
                if nesting == 1:
                    last_kind = following.kind
                    last_end = following.end
                nesting += 1
            elif following.kind == "]":
                nesting -= 1
                if nesting == 0:
                    return opening.end, following.start, last_kind == ",", last_end
                if nesting == 1:
                    last_kind = following.kind
                    last_end = following.end
            elif nesting == 1:
                last_kind = following.kind
                last_end = following.end
        raise ValueError('unterminated top-level "plugin" array')
    if "plugin" in parsed:
        raise ValueError('could not safely locate top-level "plugin" array')
    return None


def jsonc_to_json(source: str) -> str:
    chars = list(source)
    index = 0
    in_string = False
    escaped = False
    while index < len(chars):
        if in_string:
            if escaped:
                escaped = False
            elif chars[index] == "\\":
                escaped = True
            elif chars[index] == '"':
                in_string = False
            index += 1
            continue
        if chars[index] == '"':
            in_string = True
            index += 1
            continue
        if index + 1 < len(chars) and chars[index] == "/" and chars[index + 1] == "/":
            end = source.find("\n", index + 2)
            end = len(chars) if end == -1 else end
            for cursor in range(index, end):
                chars[cursor] = " "
            index = end
            continue
        if index + 1 < len(chars) and chars[index] == "/" and chars[index + 1] == "*":
            end = source.find("*/", index + 2)
            if end == -1:
                raise ValueError("unterminated block comment")
            for cursor in range(index, end + 2):
                if chars[cursor] != "\n":
                    chars[cursor] = " "
            index = end + 2
            continue
        index += 1

    index = 0
    in_string = False
    escaped = False
    while index < len(chars):
        char = chars[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            index += 1
            continue
        if char == ",":
            cursor = index + 1
            while cursor < len(chars) and chars[cursor].isspace():
                cursor += 1
            if cursor < len(chars) and chars[cursor] in "]}":
                chars[index] = " "
        index += 1
    return "".join(chars)


def patch(source: str, plugin_path: str) -> str:
    if not source.strip():
        return json.dumps(
            {"$schema": "https://opencode.ai/tui.json", "plugin": [plugin_path]},
            indent=2,
        ) + "\n"

    parsed = json.loads(jsonc_to_json(source))
    if not isinstance(parsed, dict):
        raise ValueError("tui.json root must be an object")

    configured = parsed.get("plugin", [])
    if not isinstance(configured, list):
        raise ValueError('top-level "plugin" must be an array')
    specs = [item[0] if isinstance(item, list) and item else item for item in configured]
    if plugin_path in specs:
        return source

    bounds = root_plugin_array(source, parsed)
    encoded = json.dumps(plugin_path)
    if bounds is not None:
        _opening_end, closing_start, trailing_comma, last_end = bounds
        prefix = source[:closing_start].rstrip()
        whitespace = source[len(prefix) : closing_start]
        comment_tail = source[last_end:closing_start]
        separator = "" if not configured or trailing_comma else ("\n," if "//" in comment_tail else ",")
        return prefix + separator + " " + encoded + whitespace + source[closing_start:]

    stream = tokens(source)
    depth = 0
    closing_start = -1
    for token in stream:
        if token.kind == "{":
            depth += 1
        elif token.kind == "}":
            depth -= 1
            if depth == 0:
                closing_start = token.start
                break
    if closing_start < 0:
        raise ValueError("tui.json root object is not closed")

    prefix = source[:closing_start].rstrip()
    last_token = next((item for item in reversed(stream) if item.start < closing_start), None)
    trailing_comma = last_token is not None and last_token.kind == ","
    comma = "" if not parsed or trailing_comma else ("\n," if "//" in prefix.splitlines()[-1] else ",")
    addition = f'{comma}\n  "plugin": [{encoded}]\n'
    return prefix + addition + source[closing_start:]


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: patch-tui-config.py CONFIG PLUGIN", file=sys.stderr)
        return 2
    config = pathlib.Path(sys.argv[1])
    plugin_path = str(pathlib.Path(sys.argv[2]).resolve())
    try:
        source = config.read_text(encoding="utf-8") if config.exists() else ""
        result = patch(source, plugin_path)
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text(result, encoding="utf-8")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: could not safely patch {config}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
