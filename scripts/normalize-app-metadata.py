#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from app_packaging import MetadataError, normalize_metadata, write_metadata_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Normalize Space app packaging metadata.")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--space-version", required=True)
    parser.add_argument("--app-name", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--app-id", default=None)
    parser.add_argument("--entrypoint", default="main")
    parser.add_argument("--assets-dir", default="assets")
    parser.add_argument("--icon-path", default=None)
    parser.add_argument("--linux-profile", default="full")
    parser.add_argument("--release-version", default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        metadata = normalize_metadata(
            repo_root=args.repo_root,
            space_version=args.space_version,
            app_name=args.app_name,
            app_id=args.app_id,
            entrypoint=args.entrypoint,
            assets_dir=args.assets_dir,
            icon_path=args.icon_path,
            linux_profile=args.linux_profile,
            release_version=args.release_version,
        )
        output = write_metadata_json(metadata, args.output)
    except MetadataError as error:
        print(str(error), file=sys.stderr)
        return 2

    print(Path(output))
    return 0


if __name__ == "__main__":
    sys.exit(main())
