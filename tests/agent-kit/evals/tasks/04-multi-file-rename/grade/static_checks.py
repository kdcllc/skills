"""Static checks for 04-multi-file-rename. Usage: static_checks.py docs|ast <project-dir>

Exit 0 when the check passes, 1 when it fails. Reads only; never writes.
"""
import ast
import os
import re
import sys

KEY_SHAPED = re.compile(r"""(?<![\w])["']?timeout["']?\s*[:=]""")
NEW_KEY = re.compile(r"""["']?timeout_s["']?\s*[:=]""")
FENCE = re.compile(r"^```[^\n]*\n(.*?)^```", re.S | re.M)
SKIP_DIRS = {".git", ".claude", "_kit", "_loop", "_memory", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".venv", "venv"}


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def check_docs(root):
    ok = True
    example = read(os.path.join(root, "config.example.json"))
    if KEY_SHAPED.search(example) or not NEW_KEY.search(example):
        ok = False
    blocks = FENCE.findall(read(os.path.join(root, "README.md")))
    if any(KEY_SHAPED.search(b) for b in blocks) or not any(NEW_KEY.search(b) for b in blocks):
        ok = False
    return ok


def sources(root):
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        rel = os.path.relpath(base, root)
        if rel == "tests" or rel.startswith("tests" + os.sep):
            continue
        for name in files:
            if name.endswith(".py"):
                yield os.path.join(base, name)


def warns(func):
    for node in ast.walk(func):
        if isinstance(node, ast.Name) and node.id == "DeprecationWarning":
            return True
        if isinstance(node, ast.Attribute) and node.attr == "DeprecationWarning":
            return True
    return False


def parents_map(tree):
    parents = {}
    for node in ast.walk(tree):
        for child in ast.iter_child_nodes(node):
            parents[child] = node
    return parents


def inside_warning_function(node, parents):
    while node in parents:
        node = parents[node]
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and warns(node):
            return True
    return False


def has_timeout(node):
    return any(isinstance(n, ast.Constant) and n.value == "timeout" for n in ast.walk(node))


def callee_name(call):
    if isinstance(call.func, ast.Name):
        return call.func.id
    if isinstance(call.func, ast.Attribute):
        return call.func.attr
    return None


def check_ast(root):
    trees = {}
    for path in sources(root):
        trees[path] = ast.parse(read(path), filename=path)
    parents = {p: parents_map(t) for p, t in trees.items()}
    warn_funcs = set()  # names of project functions that emit DeprecationWarning
    for tree in trees.values():
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and warns(node):
                warn_funcs.add(node.name)
    module_names = {}  # name -> constants held by a module-level `NAME = <value with 'timeout'>`
    for tree in trees.values():
        for stmt in tree.body:
            if isinstance(stmt, ast.Assign) and len(stmt.targets) == 1:
                target, value = stmt.targets[0], stmt.value
            elif isinstance(stmt, ast.AnnAssign) and stmt.value is not None:
                target, value = stmt.target, stmt.value
            else:
                continue
            if isinstance(target, ast.Name) and has_timeout(value):
                held = module_names.setdefault(target.id, set())
                held.update(n for n in ast.walk(value) if isinstance(n, ast.Constant) and n.value == "timeout")
    held_all = set().union(*module_names.values()) if module_names else set()
    ok = True
    for path, tree in trees.items():
        for node in ast.walk(tree):
            if not (isinstance(node, ast.Constant) and node.value == "timeout"):
                continue
            if inside_warning_function(node, parents[path]) or node in held_all:
                continue
            parent = parents[path].get(node)
            if isinstance(parent, ast.keyword):
                parent = parents[path].get(parent)
            if isinstance(parent, ast.Call) and callee_name(parent) in warn_funcs:
                continue  # passed straight to a function that emits the warning
            ok = False
    for name in module_names:
        for path, tree in trees.items():
            for node in ast.walk(tree):
                used = (
                    (isinstance(node, ast.Name) and node.id == name and isinstance(node.ctx, ast.Load))
                    or (isinstance(node, ast.Attribute) and node.attr == name)
                    or (isinstance(node, ast.alias) and node.name == name)
                )
                if used and not inside_warning_function(node, parents[path]):
                    ok = False
    return ok


def main(argv):
    mode, root = argv[1], argv[2]
    return 0 if (check_docs(root) if mode == "docs" else check_ast(root)) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
