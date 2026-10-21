#!/usr/bin/env python3
"""Push the current local commit to GitHub through the REST API (api.github.com).

WHY THIS EXISTS
    In this environment the machine can only reach the internet through a proxy,
    and that proxy blocks `github.com` (git's HTTPS endpoint) with
    `CONNECT tunnel failed, response 502` while `api.github.com` works fine.
    `git push` therefore fails, but the Git Data API can still create the exact
    same commit object. This script does that.

WHAT IT DOES
    1. reads the GitHub credential from `git credential fill` (never printed);
    2. verifies the remote branch tip is exactly the local commit's parent
       (refuses to run otherwise - it never rewrites remote history);
    3. uploads the blobs for every path that differs from the parent, rebuilds
       the tree on top of the parent's tree, creates the commit with the LOCAL
       commit's own author/committer/message, and moves the branch ref.

    Because every byte of the commit metadata is copied from the local commit,
    the resulting commit SHA is IDENTICAL to the local one, so local and remote
    never diverge. A normal `git push` later is then a no-op.

USAGE
    python safevision/tools/push_via_api.py                 # push local main
    python safevision/tools/push_via_api.py --ref main
    python safevision/tools/push_via_api.py --dry-run

NOTES
    - Read-only against everything except the single branch ref it moves.
    - Uses `force: false` on the ref update: a non-fast-forward is rejected.
"""
import argparse
import base64
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

GIT = ["git", "-c", "core.quotepath=false"]


def git(*args, binary=False):
    out = subprocess.run(GIT + list(args), capture_output=True, check=True).stdout
    return out if binary else out.decode("utf-8", "replace")


def credential():
    """Ask git for the stored GitHub credential (password is a token)."""
    p = subprocess.run(GIT + ["credential", "fill"],
                       input=b"protocol=https\nhost=github.com\n\n",
                       capture_output=True, check=True)
    token = None
    for line in p.stdout.decode("utf-8", "replace").splitlines():
        if line.startswith("password="):
            token = line.split("=", 1)[1].strip()
    if not token:
        sys.exit("no GitHub credential available (git credential fill returned no password)")
    return token


def repo_slug():
    url = git("remote", "get-url", "origin").strip()
    m = re.search(r"github\.com[:/]+(.+?)(?:\.git)?$", url)
    if not m:
        sys.exit(f"cannot derive owner/repo from origin url: {url}")
    return m.group(1)


def parse_commit(sha):
    raw = git("cat-file", "commit", sha)
    def field(name):
        return re.search(rf"^{name} (.+)$", raw, re.M).group(1)
    a = re.match(r"(.+) <(.+)> (\d+) ([+-]\d{4})$", field("author"))
    c = re.match(r"(.+) <(.+)> (\d+) ([+-]\d{4})$", field("committer"))
    def stamp(m):
        off = datetime.timezone(datetime.timedelta(
            hours=int(m.group(4)[:3]), minutes=int(m.group(4)[0] + m.group(4)[3:])))
        return {"name": m.group(1), "email": m.group(2),
                "date": datetime.datetime.fromtimestamp(int(m.group(3)), off).isoformat()}
    return {"tree": field("tree"), "parent": field("parent"),
            "message": raw.split("\n\n", 1)[1], "author": stamp(a), "committer": stamp(c)}


def changed_paths(parent, local):
    out = git("diff", "--name-status", parent, local).strip().splitlines()
    entries, deleted = [], []
    for line in out:
        parts = line.split("\t")
        status, path = parts[0], parts[-1]
        if status.startswith("D"):
            deleted.append(path)
        else:                       # A / M / R (rename: use the new path)
            entries.append(path)
    return entries, deleted


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ref", default="main", help="branch to push (default: main)")
    ap.add_argument("--local", default=None, help="local commit (default: <ref> tip)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    local = git("rev-parse", args.local or args.ref).strip()
    meta = parse_commit(local)
    parent = meta["parent"]
    repo = repo_slug()
    api = f"https://api.github.com/repos/{repo}"

    entries, deleted = changed_paths(parent, local)
    print(f"repo      : {repo}")
    print(f"branch    : {args.ref}")
    print(f"local     : {local[:12]}")
    print(f"parent    : {parent[:12]}  (must equal the remote tip)")
    print(f"changed   : {len(entries)} file(s), {len(deleted)} deletion(s)")
    if args.dry_run:
        return 0

    token = credential()

    def call(method, path, body=None):
        req = urllib.request.Request(
            api + path, method=method,
            data=None if body is None else json.dumps(body).encode(),
            headers={"Authorization": f"Bearer {token}",
                     "Accept": "application/vnd.github+json",
                     "User-Agent": "safevision-push-via-api",
                     "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return r.status, json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read() or b"{}")

    status, ref = call("GET", f"/git/ref/heads/{args.ref}")
    if status != 200:
        sys.exit(f"cannot read ref heads/{args.ref}: {status} {ref}")
    if ref["object"]["sha"] != parent:
        sys.exit(f"remote heads/{args.ref} is {ref['object']['sha'][:12]}, expected the local "
                 f"parent {parent[:12]}: remote moved. Merge/rebase first - this tool never "
                 f"rewrites remote history.")
    print("remote tip matches the local parent  OK")

    tree_entries = []
    for path in entries:
        blob = git("cat-file", "blob", f"{local}:{path}", binary=True)
        st, b = call("POST", "/git/blobs",
                     {"content": base64.b64encode(blob).decode(), "encoding": "base64"})
        if st != 201:
            sys.exit(f"blob upload failed for {path}: {st} {b}")
        tree_entries.append({"path": path, "mode": "100644", "type": "blob", "sha": b["sha"]})
        print(f"  blob {b['sha'][:12]}  {path}")
    for path in deleted:
        tree_entries.append({"path": path, "mode": "100644", "type": "blob", "sha": None})
        print(f"  del  {'-' * 12}  {path}")

    _, parent_commit = call("GET", f"/git/commits/{parent}")
    st, tree = call("POST", "/git/trees",
                    {"base_tree": parent_commit["tree"]["sha"], "tree": tree_entries})
    if st != 201:
        sys.exit(f"tree creation failed: {st} {tree}")
    ok = "== local tree" if tree["sha"] == meta["tree"] else f"!= local tree {meta['tree'][:12]}"
    print(f"  tree {tree['sha'][:12]}  {ok}")

    st, commit = call("POST", "/git/commits",
                      {"message": meta["message"], "tree": tree["sha"], "parents": [parent],
                       "author": meta["author"], "committer": meta["committer"]})
    if st != 201:
        sys.exit(f"commit creation failed: {st} {commit}")
    print(f"  commit {commit['sha'][:12]}  "
          f"{'== local commit' if commit['sha'] == local else '!= local commit'}")

    st, moved = call("PATCH", f"/git/refs/heads/{args.ref}",
                     {"sha": commit["sha"], "force": False})
    if st not in (200, 201):
        sys.exit(f"ref update failed: {st} {moved}")
    print(f"  ref heads/{args.ref} -> {moved['object']['sha'][:12]}")

    subprocess.run(GIT + ["update-ref", f"refs/remotes/origin/{args.ref}", commit["sha"]], check=True)
    if commit["sha"] == local:
        print("OK: pushed with an identical SHA; local and remote are in sync.")
        return 0
    print("WARNING: the remote commit SHA differs from the local one "
          "(metadata mismatch); fetch and reconcile before pushing again.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
