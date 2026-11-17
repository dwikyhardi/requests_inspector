import re
import subprocess
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import urlopen


def main():
    subprocess.run(
        ["git", "merge-base", "--is-ancestor", "HEAD", "origin/main"], check=True
    )
    pubspec = Path("pubspec.yaml").read_text()
    version = re.search(r"^version:\s*(\S+)\s*$", pubspec, re.MULTILINE)
    if not version or not re.fullmatch(
        r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?",
        version[1],
    ):
        raise ValueError("Expected a semantic version in pubspec.yaml")
    version = version[1]
    package = "requests_inspector_plus"
    url = f"https://pub.dev/api/packages/{package}/versions/{quote(version, safe='')}"
    try:
        with urlopen(url, timeout=30):
            print(f"{package} {version} is already published; skipping.")
            return
    except HTTPError as error:
        if error.code != 404:
            raise

    subprocess.run(["flutter", "pub", "publish", "--dry-run"], check=True)
    tag = f"{package}-v{version}"
    exists = subprocess.run(["git", "show-ref", "--verify", "--quiet", f"refs/tags/{tag}"])
    if exists.returncode == 0:
        tagged_commit = subprocess.check_output(
            ["git", "rev-list", "-n", "1", tag], text=True
        ).strip()
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
        if tagged_commit != head:
            raise RuntimeError(f"{tag} already points to a different commit")
        print(f"{tag} already exists; retry its publish workflow if necessary.")
        return
    if exists.returncode != 1:
        raise RuntimeError("Could not check existing release tags")

    subprocess.run(["git", "tag", tag], check=True)
    subprocess.run(["git", "push", "origin", f"refs/tags/{tag}"], check=True)


if __name__ == "__main__":
    main()
