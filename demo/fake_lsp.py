#!/usr/bin/env python3

import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse


FUNCTION = 12


def read_message():
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            break
        key, value = line.decode("utf-8").split(":", 1)
        headers[key.strip().lower()] = value.strip()

    length = int(headers.get("content-length", "0"))
    if length <= 0:
        return None
    body = sys.stdin.buffer.read(length)
    if not body:
        return None
    return json.loads(body)


def send_message(payload):
    encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(encoded)}\r\n\r\n".encode("utf-8"))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


def path_from_uri(uri):
    parsed = urlparse(uri)
    return Path(unquote(parsed.path))


def uri_from_path(path):
    return Path(path).resolve().as_uri()


def project_root(path):
    path = path.resolve()
    for parent in (path,) + tuple(path.parents):
        if (parent / "package.json").exists():
            return parent
    return path.parent


def location(path, line, character, length):
    return {
        "uri": uri_from_path(path),
        "range": {
            "start": {"line": line, "character": character},
            "end": {"line": line, "character": character + length},
        },
    }


def call_item(name, path, line, character, length):
    return {
        "name": name,
        "kind": FUNCTION,
        "uri": uri_from_path(path),
        "range": {
            "start": {"line": line, "character": character},
            "end": {"line": line, "character": character + length},
        },
        "selectionRange": {
            "start": {"line": line, "character": character},
            "end": {"line": line, "character": character + length},
        },
    }


def dataset(root):
    user_service = root / "src" / "user_service.ts"
    users = root / "src" / "users.ts"
    user_controller = root / "src" / "user_controller.ts"
    user_directory = root / "src" / "user_directory.ts"
    tests = root / "tests" / "user_service_test.ts"
    flow_tests = root / "tests" / "user_flow_test.ts"
    return {
        "createUser": {
            "definition": location(user_service, 0, 16, 10),
            "references": [
                location(users, 0, 9, 10),
                location(users, 4, 9, 10),
                location(user_controller, 0, 9, 10),
                location(user_controller, 3, 9, 10),
                location(user_controller, 11, 16, 10),
                location(user_directory, 0, 9, 10),
                location(user_directory, 4, 34, 10),
                location(user_service, 20, 25, 10),
                location(tests, 0, 9, 10),
                location(tests, 4, 11, 10),
                location(flow_tests, 0, 9, 10),
                location(flow_tests, 4, 18, 10),
            ],
            "call_item": call_item("createUser", user_service, 0, 16, 10),
            "incoming": [
                {
                    "from": call_item("openUsersPage", users, 2, 16, 13),
                    "fromRanges": [{"start": {"line": 4, "character": 9}, "end": {"line": 4, "character": 19}}],
                },
                {
                    "from": call_item("bootstrapUser", user_controller, 2, 16, 13),
                    "fromRanges": [{"start": {"line": 3, "character": 9}, "end": {"line": 3, "character": 19}}],
                },
                {
                    "from": call_item("buildUserCard", user_controller, 10, 16, 13),
                    "fromRanges": [{"start": {"line": 11, "character": 16}, "end": {"line": 11, "character": 26}}],
                },
                {
                    "from": call_item("ensureDirectoryUser", user_directory, 2, 16, 19),
                    "fromRanges": [{"start": {"line": 4, "character": 34}, "end": {"line": 4, "character": 44}}],
                },
                {
                    "from": call_item("mergeUserDisplayName", user_service, 18, 16, 20),
                    "fromRanges": [{"start": {"line": 20, "character": 25}, "end": {"line": 20, "character": 35}}],
                },
            ],
        },
        "findUser": {
            "definition": location(user_service, 7, 16, 8),
            "references": [
                location(users, 0, 21, 8),
                location(users, 3, 18, 8),
                location(user_directory, 0, 21, 8),
                location(user_directory, 3, 18, 8),
                location(user_service, 19, 18, 8),
            ],
            "call_item": call_item("findUser", user_service, 7, 16, 8),
            "incoming": [
                {
                    "from": call_item("openUsersPage", users, 2, 16, 13),
                    "fromRanges": [{"start": {"line": 3, "character": 18}, "end": {"line": 3, "character": 26}}],
                },
                {
                    "from": call_item("ensureDirectoryUser", user_directory, 2, 16, 19),
                    "fromRanges": [{"start": {"line": 3, "character": 18}, "end": {"line": 3, "character": 26}}],
                },
                {
                    "from": call_item("mergeUserDisplayName", user_service, 18, 16, 20),
                    "fromRanges": [{"start": {"line": 19, "character": 18}, "end": {"line": 19, "character": 26}}],
                },
            ],
        },
        "updateUser": {
            "definition": location(user_service, 14, 16, 10),
            "references": [
                location(user_controller, 0, 21, 10),
                location(user_controller, 7, 9, 10),
                location(flow_tests, 0, 21, 10),
                location(flow_tests, 5, 11, 10),
            ],
            "call_item": call_item("updateUser", user_service, 14, 16, 10),
            "incoming": [
                {
                    "from": call_item("renameUser", user_controller, 6, 16, 10),
                    "fromRanges": [{"start": {"line": 7, "character": 9}, "end": {"line": 7, "character": 19}}],
                }
            ],
        },
    }


def symbol_at(uri, position):
    path = path_from_uri(uri)
    try:
        line = path.read_text(encoding="utf-8").splitlines()[position["line"]]
    except (FileNotFoundError, IndexError):
        return None

    for match in re.finditer(r"[A-Za-z_][A-Za-z0-9_]*", line):
        start, end = match.span()
        if start <= position["character"] <= end:
            return match.group(0)
    return None


def response_for(request):
    method = request.get("method")
    params = request.get("params") or {}

    if method == "initialize":
        return {
            "capabilities": {
                "positionEncoding": "utf-16",
                "textDocumentSync": 1,
                "definitionProvider": True,
                "referencesProvider": True,
                "callHierarchyProvider": True,
            }
        }

    if method in {"shutdown"}:
        return None

    if method == "textDocument/definition":
        uri = params["textDocument"]["uri"]
        root = project_root(path_from_uri(uri))
        symbol = symbol_at(uri, params["position"])
        entry = dataset(root).get(symbol)
        return [entry["definition"]] if entry else []

    if method == "textDocument/references":
        uri = params["textDocument"]["uri"]
        root = project_root(path_from_uri(uri))
        symbol = symbol_at(uri, params["position"])
        entry = dataset(root).get(symbol)
        return entry["references"] if entry else []

    if method == "textDocument/prepareCallHierarchy":
        uri = params["textDocument"]["uri"]
        root = project_root(path_from_uri(uri))
        symbol = symbol_at(uri, params["position"])
        entry = dataset(root).get(symbol)
        return [entry["call_item"]] if entry else []

    if method == "callHierarchy/incomingCalls":
        item = params.get("item") or {}
        uri = item.get("uri")
        if not uri:
            return []
        root = project_root(path_from_uri(uri))
        entry = dataset(root).get(item.get("name"))
        return entry["incoming"] if entry else []

    return None


def main():
    while True:
        message = read_message()
        if message is None:
            return

        method = message.get("method")
        if method == "exit":
            return

        if "id" not in message:
            continue

        try:
            result = response_for(message)
            send_message({"jsonrpc": "2.0", "id": message["id"], "result": result})
        except Exception as exc:
            send_message({
                "jsonrpc": "2.0",
                "id": message["id"],
                "error": {"code": -32603, "message": str(exc)},
            })


if __name__ == "__main__":
    main()
