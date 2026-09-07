#!/usr/bin/env python3
"""Reuse the installer's private identity for direct Xcode builds. No device access."""

import os
import sys
import tempfile

from install_ios import ROOT, SUPPORT, InstallError, configured_bundle_identifier, configured_team


def main():
    team = configured_team()
    bundle = configured_bundle_identifier()
    if not team or not bundle:
        raise InstallError(f"请先在 {SUPPORT / 'Signing.json'} 填写 teamIdentifier 和 bundleIdentifier。")
    target = ROOT / "Configuration/Signing.xcconfig.local"
    content = ("// Local signing only. Ignored by Git. Generated from the installer's Signing.json.\n"
               f"DEVELOPMENT_TEAM = {team}\n"
               f"SCHEDULE_BUNDLE_IDENTIFIER = {bundle}\n")
    # Write atomically with owner-only permissions; don't expose identifiers in output.
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=target.parent, delete=False) as output:
            temp_path = output.name
            output.write(content)
        os.replace(temp_path, target)
    finally:
        if temp_path and os.path.exists(temp_path):
            os.unlink(temp_path)
    print("已配置 Xcode：手机与手表沿用本机原 Team 和应用标识。个人配置已被 Git 忽略。")


if __name__ == "__main__":
    try:
        main()
    except (InstallError, OSError, ValueError, KeyError) as error:
        print(f"配置失败：{error}", file=sys.stderr)
        sys.exit(1)
