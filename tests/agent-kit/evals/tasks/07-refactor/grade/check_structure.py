"""Hidden check: the per-line formatting block is not duplicated.

Each function body in the non-test Python files is scanned, nested functions
and classes excluded; the module body is not scanned. A simple statement in
that body (docstrings skipped) is a formatting statement when it contains an
ljust/rjust/center/format call, a builtin format() call, a
`"..." % ...` expression, an f-string field with a format spec, or a
slice. Every Name in it is replaced by one placeholder; constants are kept.
The check fails when the same normalized formatting statement occurs in two
or more functions. The seed repeats the block in three functions, so it
fails; one shared helper passes however its widths are spelled.
"""
import ast
import copy
import os
import sys

FMT_CALLS = {"ljust", "rjust", "center", "format"}
NESTED = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)


class Normalize(ast.NodeTransformer):
    def visit_Name(self, node):
        return ast.copy_location(ast.Name(id="_", ctx=node.ctx), node)


def child_bodies(stmt):
    """Statement lists nested in a compound statement."""
    for value in ast.iter_fields(stmt):
        field = value[1]
        if not isinstance(field, list):
            continue
        for item in field:
            if isinstance(item, ast.stmt):
                yield field
                break
            body = getattr(item, "body", None)  # except handlers, match cases
            if isinstance(body, list):
                yield body


def simple_statements(body):
    """Simple statements of one function, nested functions and classes excluded."""
    for stmt in body:
        if isinstance(stmt, NESTED):
            continue
        bodies = list(child_bodies(stmt))
        if bodies:
            for sub in bodies:
                yield from simple_statements(sub)
        else:
            yield stmt


def is_docstring(stmt):
    return (isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant)
            and isinstance(stmt.value.value, str))


def is_formatting(stmt):
    stack = [stmt]
    while stack:
        node = stack.pop()
        if isinstance(node, NESTED):
            continue
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr in FMT_CALLS):
            return True
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == "format"):
            return True
        if (isinstance(node, ast.BinOp) and isinstance(node.op, ast.Mod)
                and isinstance(node.left, ast.Constant)
                and isinstance(node.left.value, str)):
            return True
        if isinstance(node, ast.FormattedValue) and node.format_spec is not None:
            return True
        if isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Slice):
            return True
        stack.extend(ast.iter_child_nodes(node))
    return False


def normalized(stmt):
    return ast.dump(Normalize().visit(copy.deepcopy(stmt)))


proj = os.environ["PROJ_DIR"]
seen = {}
for root, dirs, files in os.walk(proj):
    dirs[:] = sorted(d for d in dirs if d not in ("tests", "__pycache__"))
    for name in sorted(files):
        if not name.endswith(".py"):
            continue
        path = os.path.join(root, name)
        tree = ast.parse(open(path, encoding="utf-8").read())
        for fn in ast.walk(tree):
            if not isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            for stmt in simple_statements(fn.body):
                if is_docstring(stmt) or not is_formatting(stmt):
                    continue
                seen.setdefault(normalized(stmt), set()).add((path, fn.lineno))
dups = [key for key, where in seen.items() if len(where) > 1]
print("formatting statements repeated across functions:", len(dups))
sys.exit(1 if dups else 0)
