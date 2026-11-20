import hashlib
import os
import re
import subprocess
import sys
from collections import Counter
from itertools import groupby
from pathlib import Path

from pygments.lexer import inherit
from pygments.lexers import get_lexer_by_name
from pygments.lexers.shell import BashLexer
from pygments.token import Comment, String, Text
from unidiff import PatchSet


BASELINE = Path("modules/maintenance/development/comments.allow")
LANGUAGES = {
    ".nix": "nix", ".sh": "bash", ".envrc": "bash", ".py": "python",
    ".lua": "lua", ".yaml": "yaml", ".yml": "yaml", ".toml": "toml",
    "justfile": "bash", ".just": "bash", ".c": "c", ".h": "cpp", ".cpp": "cpp",
    ".js": "javascript", ".ts": "typescript", ".patch": "patch",
    ".gitignore": "line", ".gitattributes": "line", "packages/update.list": "registry",
}
DIRECTIVE = re.compile(r"#\s*shellcheck\s+(?:(?:shell|disable|enable|source|source-path|external-sources|extended-analysis)=\S+\s*)+")
NIX_STRING = re.compile(r"^([^\n]*)''\n(.*?)^[ \t]*''(?=[;)+,\s]|\Z)", re.M | re.S)
SHELL_PRODUCER = re.compile(
    r"writeShell(?:Script|Application)|runCommand|home\.activation|(?:Phase|Build|Patch|Command|ShellInit|script)\s*="
)
CONFIG_PRODUCER = re.compile(r'\.(?:dae|conf)"\.(?:content|text)\s*=|^extraConfig\s*=')


class BashWordHashLexer(BashLexer):
    tokens = {"basic": [(r"(?<=[^\s;&|()<>])#", Text), inherit]}


def language(path):
    return LANGUAGES.get(str(path)) or LANGUAGES.get(path.suffix or path.name)


def is_comment(token):
    kind = token[1]
    return kind in Comment and kind not in {Comment.Preproc, Comment.PreprocFile}


def comments(source, lang):
    if lang in {"line", "registry"}:
        for n, line in enumerate(source.splitlines(), 1):
            if (line.lstrip() if lang == "registry" else line).startswith("#"):
                yield n, line.strip()
        return
    lexer = BashWordHashLexer() if lang == "bash" else get_lexer_by_name(lang)
    tokens = lexer.get_tokens_unprocessed(source.removesuffix("\n") + "\n")
    for comment, parts in groupby(tokens, is_comment):
        if not comment:
            continue
        offset, _, first = next(parts)
        body = first + "".join(text for _, _, text in parts)
        for n, line in enumerate(body.splitlines(), source.count("\n", 0, offset) + 1):
            if (n == 1 and offset == 0 and line.startswith("#!")) or (lang == "bash" and DIRECTIVE.fullmatch(line)):
                continue
            if line.strip():
                yield n, line.strip()


def inventory(path, lang):
    source = path.read_text()
    if lang == "patch":
        for patched in PatchSet(source.splitlines(keepends=True)):
            target = language(Path(patched.path))
            if not target:
                continue
            for hunk in patched:
                rows = [row for row in hunk if row.is_added or row.is_context]
                for n, line in comments("".join(row.value for row in rows), target):
                    if rows[n - 1].is_added:
                        yield rows[n - 1].diff_line_no, line
        return
    yield from comments(source, lang)
    if lang == "nix":
        for m in NIX_STRING.finditer(source):
            head = m[1].strip()
            if head in {"", "text ="}:
                indent = len(m[1]) - len(m[1].lstrip())
                parents = reversed(source[:m.start()].splitlines())
                head = next((s.strip() for s in parents if s.strip() and len(s) - len(s.lstrip()) < indent), head)
            if "security.polkit.extraConfig" in head:
                embedded = "javascript"
            elif SHELL_PRODUCER.search(head) or CONFIG_PRODUCER.search(head):
                embedded = "bash"
            else:
                continue
            for n, line in comments(m[2].replace("''${", "${"), embedded):
                yield source.count("\n", 0, m.start(2)) + n, line
    elif lang == "bash" and path.suffix == ".sh":
        for pos, kind, value in BashWordHashLexer().get_tokens_unprocessed(source):
            if kind != String.Single or not source[:pos].rstrip().endswith("--expr"):
                continue
            command = source[:pos].replace("\\\n", " ")
            if re.search(r"\bnix(?:-instantiate|\s+eval)\b[^\n]*--expr\s*\Z", command):
                for n, line in comments(value[1:-1], "nix"):
                    yield source.count("\n", 0, pos) + n, line


def main():
    if sys.argv[1:]:
        sys.exit("usage: check-comments (from the repository root)")
    allowed = Counter()
    for row in BASELINE.read_text().splitlines():
        path, *keys = row.split("\t")
        allowed.update((path, key) for key in keys)
    failed = False
    for raw in subprocess.check_output(["git", "ls-files", "-z"]).split(b"\0")[:-1]:
        path = Path(os.fsdecode(raw))
        lang = language(path)
        if not lang or path.is_symlink() or not path.is_file():
            continue
        if path.name in {"secrets.yaml", "secrets.yml"} or ".sops." in path.name or "secrets" in path.parts:
            continue
        for n, line in inventory(path, lang):
            key = hashlib.sha256(line.encode()).hexdigest()[:16]
            entry = str(path), key
            if allowed[entry]:
                allowed[entry] -= 1
            else:
                print(f"{path}:{n}: unreviewed comment [{key}]: {line}", file=sys.stderr)
                failed = True
    for (path, key), count in allowed.items():
        if count:
            print(f"{path}: remove unused allowance {key} (x{count})", file=sys.stderr)
            failed = True
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
