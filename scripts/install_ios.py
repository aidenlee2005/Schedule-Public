#!/usr/bin/env python3
"""Build, back up, and update a connected iPhone. Python standard library only."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from urllib.parse import unquote, urlparse
import uuid


ROOT = Path(__file__).resolve().parent.parent
SUPPORT = Path.home() / "Library/Application Support/ScheduleInstaller"
BUILD = Path.home() / "Library/Caches/ScheduleInstaller/DerivedData"
STORE = Path("Library/Application Support/ScheduleStore_v2.store")


class InstallError(Exception):
    pass


def say(message):
    print(message, flush=True)


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def configured_team(explicit=None):
    """Keep a personal signing identity outside the publishable repository."""
    team = explicit
    local = SUPPORT / "Signing.json"
    if not team and local.exists():
        team = json.loads(local.read_text())["teamIdentifier"]
    if team is not None and (not isinstance(team, str) or not re.fullmatch(r"[A-Z0-9]{10}", team)):
        raise InstallError(f"签名 Team ID 应为 10 位大写字母/数字。请检查 --team 或 {local}。")
    return team


def configured_bundle_identifier():
    """A private install keeps its original app container even if public defaults change."""
    local = SUPPORT / "Signing.json"
    if not local.exists():
        return None
    identifier = json.loads(local.read_text()).get("bundleIdentifier")
    if identifier is not None and (not isinstance(identifier, str) or not re.fullmatch(
            r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", identifier)):
        raise InstallError(f"本机 bundleIdentifier 格式无效，请检查 {local}。")
    return identifier


def configured_watch_identifier():
    local = SUPPORT / "Signing.json"
    return json.loads(local.read_text()).get("watchIdentifier") if local.exists() else None


def available(device):
    connection = device.get("connectionProperties", {})
    hardware = device.get("hardwareProperties", {})
    return (hardware.get("deviceType") in ("iPhone", "iPad")
            and connection.get("pairingState") == "paired"
            and connection.get("tunnelState") in ("connected", "disconnected"))


def available_watch(device):
    connection = device.get("connectionProperties", {})
    return (device.get("hardwareProperties", {}).get("deviceType") == "appleWatch"
            and connection.get("pairingState") == "paired"
            and connection.get("tunnelState") in ("connected", "disconnected"))


def select_watch(devices, requested):
    matches = [d for d in devices if available_watch(d) and requested in (
        d["identifier"], d.get("hardwareProperties", {}).get("udid"),
        d.get("deviceProperties", {}).get("name"))]
    if len(matches) != 1:
        raise InstallError("无法唯一确定指定的 Apple Watch。请确认手表已配对、解锁、开启开发者模式，"
                           "并用 --list-devices 查看标识。")
    return matches[0]


def describe(device):
    name = device.get("deviceProperties", {}).get("name", "Unnamed")
    model = device.get("hardwareProperties", {}).get("marketingName", "iOS device")
    state = "可连接" if available(device) or available_watch(device) else "未连接"
    return f"{name} · {model} · {state} · {device['identifier']}"


def select_device(devices, requested=None, interactive=False):
    candidates = [d for d in devices if available(d)]
    if requested:
        candidates = [d for d in candidates if requested in (
            d["identifier"], d.get("hardwareProperties", {}).get("udid"),
            d.get("deviceProperties", {}).get("name"))]
    if not candidates:
        raise InstallError("找不到可连接的 iPhone/iPad。请接上数据线、解锁并选择“信任此电脑”，"
                           "在 Xcode → Window → Devices and Simulators 中确认设备可用。")
    if len(candidates) == 1:
        return candidates[0]
    say("检测到多台设备，请选择本次安装的手机：")
    for index, device in enumerate(candidates, 1):
        say(f"  {index}. {describe(device)}")
    if not interactive:
        raise InstallError("多台设备可连接，请用 --device <设备标识> 指定目标。")
    try:
        index = int(input("输入编号：")) - 1
        if 0 <= index < len(candidates):
            return candidates[index]
    except (ValueError, EOFError):
        pass
    raise InstallError("未选择有效设备，已停止。")


class Commands:
    def __init__(self, directory):
        self.directory = directory
        self.serial = 0

    def run(self, args, label):
        self.serial += 1
        log = self.directory / f"{self.serial:02d}-{label}.log"
        with log.open("wb") as output:
            result = subprocess.run([str(a) for a in args], cwd=ROOT,
                                    stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            tail = "\n".join(log.read_text(errors="replace").splitlines()[-12:])
            raise InstallError(f"{label} 失败（退出码 {result.returncode}）。\n{tail}\n详情：{log}")
        return log.read_bytes()

    def device(self, args, label):
        report = self.directory / f"{self.serial + 1:02d}-{label}.json"
        self.run(["xcrun", "devicectl", *args, "--quiet", "--timeout", "180",
                  "--json-output", report], label)
        data = json.loads(report.read_text())
        if data.get("info", {}).get("outcome") != "success":
            raise InstallError(f"{label} 未成功，已停止。详情：{report}")
        return data["result"]


def inspect_package(app, device, commands):
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    commands.run(["codesign", "--verify", "--deep", "--strict", app], "verify-signature")
    raw = commands.run(["security", "cms", "-D", "-i", app / "embedded.mobileprovision"],
                       "read-profile")
    profile = plistlib.loads(raw)
    expiry = profile["ExpirationDate"].replace(tzinfo=timezone.utc)
    if expiry <= datetime.now(timezone.utc):
        raise InstallError("构建使用的签名已过期。请在 Xcode 中对这台设备运行一次，更新签名后重试。")
    udid = device["hardwareProperties"]["udid"]
    if udid not in profile.get("ProvisionedDevices", []):
        raise InstallError("签名未包含所选设备，请先在 Xcode 中对这台设备运行一次。")
    identity = {
        "bundleIdentifier": info["CFBundleIdentifier"],
        "executable": info["CFBundleExecutable"],
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "teamIdentifier": profile["TeamIdentifier"][0],
        "expiresAt": expiry.isoformat(),
    }
    say(f"签名到期：{expiry.astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')}")
    remaining = (expiry - datetime.now(timezone.utc)).total_seconds()
    if remaining < 86400:
        say("提示：当前签名剩余不足一天。Xcode 可能复用了仍有效的描述文件；本次安装不会自动变成七天。")
    return identity


def stop_app(commands, device_id, installed, executable):
    # Use the installed bundle URL, never a substring process-name match.
    bundle_url = installed.get("url")
    if not isinstance(bundle_url, str) or not bundle_url.startswith("file://"):
        raise InstallError("无法确定旧应用的进程路径，未执行备份或安装。请更新 Xcode 后重试。")
    expected = str(Path(unquote(urlparse(bundle_url).path)) / executable)

    def running_app(label):
        result = commands.device(["device", "info", "processes", "--device", device_id], label)
        processes = result.get("runningProcesses")
        if not isinstance(processes, list):
            raise InstallError("无法读取手机进程状态，未执行备份或安装。请检查设备连接后重试。")
        matches = set()
        for process in processes:
            if not isinstance(process, dict):
                raise InstallError("手机进程状态格式异常，未执行备份或安装。")
            actual = unquote(urlparse(process.get("executable", "")).path)
            if actual == expected:
                pid = process.get("processIdentifier")
                if type(pid) is not int or pid <= 0:
                    raise InstallError("无法确认 Schedule 后台进程，未执行备份或安装。")
                matches.add(pid)
        return matches

    running = running_app("list-processes")
    # SIGTERM can remain pending for a suspended iOS app. Give it a grace
    # period, then use devicectl's documented SIGKILL option for this app only.
    # Re-read exact paths and PIDs after every request; never infer termination
    # merely from a successful signal delivery, or loop indefinitely on relaunch.
    for force in (False, True):
        sent = set()
        if running:
            say("正在结束 Schedule 挂起的后台进程…" if force else "正在停止 Schedule 的后台进程…")
        for _ in range(4):
            if not running:
                return
            for pid in sorted(running - sent):
                args = ["device", "process", "terminate", "--device", device_id, "--pid", str(pid)]
                if force:
                    args.append("--kill")
                try:
                    commands.device(args, "force-stop-app" if force else "stop-app")
                except InstallError:
                    # It may exit between listing and terminating. Continue only
                    # when a fresh process list confirms that exact PID is gone.
                    remaining = running_app("check-stopped")
                    if pid in remaining:
                        raise
                sent.add(pid)
            time.sleep(0.5)
            running = running_app("check-stopped")
    if running:
        raise InstallError("Schedule 的后台进程仍未停止，或正在被系统重新唤醒，未执行备份或安装。"
                           "请暂时退出手表上的 Schedule 和 Xcode 调试后重试。")


def copy_from(commands, device_id, bundle, source, destination, label):
    destination.mkdir(parents=True, exist_ok=True)
    commands.device(["device", "copy", "from", "--device", device_id,
                     "--domain-type", "appDataContainer", "--domain-identifier", bundle,
                     "--source", source, "--destination", str(destination)], label)


def store_fingerprint(container):
    """Check a scratch copy including WAL; never open or checkpoint the raw backup."""
    source = container / STORE
    if not source.exists():
        # A successfully installed app may not have been launched even once.
        if any(container.rglob("*.store*")):
            raise InstallError("备份数据库路径与预期不符，已停止安装。")
        return None
    with tempfile.TemporaryDirectory(prefix="Schedule-store-check-") as scratch:
        database = Path(scratch) / source.name
        for suffix in ("", "-wal", "-shm"):
            file = Path(str(source) + suffix)
            if file.exists():
                shutil.copy2(file, Path(str(database) + suffix))
        connection = sqlite3.connect(str(database))
        try:
            if connection.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                raise InstallError("备份数据库完整性检查未通过，已停止安装。")
            # SQL dump includes schema and every value. Only its digest is recorded.
            digest = hashlib.sha256()
            for line in connection.iterdump():
                digest.update(line.encode("utf-8") + b"\n")
            return digest.hexdigest()
        finally:
            connection.close()


def backup_data(commands, device, bundle, run_directory):
    backup = run_directory / "backup"
    backup.mkdir(mode=0o700)
    for directory in ("Library", "Documents"):
        copy_from(commands, device, bundle, directory, backup / directory,
                  f"backup-{directory.lower()}")
    fingerprint = store_fingerprint(backup)
    files = {}
    for path in sorted(backup.rglob("*")):
        if path.is_file():
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            files[str(path.relative_to(backup))] = {
                "bytes": path.stat().st_size, "sha256": digest.hexdigest(),
            }
    write_json(run_directory / "backup-manifest.json", {
        "bundleIdentifier": bundle, "databaseDigest": fingerprint, "files": files,
        "includes": ["Library", "Documents"], "excludes": ["Keychain", "tmp"],
    })
    say(f"备份已校验：{backup}")
    return fingerprint


def update_app(commands, device, app, identity, run_directory):
    device_id = device["identifier"]
    bundle = identity["bundleIdentifier"]
    apps = commands.device(["device", "info", "apps", "--device", device_id,
                            "--include-all-apps", "--bundle-id", bundle], "find-installed")["apps"]
    installed = next((a for a in apps if a.get("bundleIdentifier") == bundle), None)
    before = None
    if installed:
        say("2/4 正在备份手机数据，请暂时不要打开 Schedule…")
        stop_app(commands, device_id, installed, identity["executable"])
        before = backup_data(commands, device_id, bundle, run_directory)
    else:
        say(f"2/4 手机没有 {bundle}，本次为首次安装。")
    say("3/4 正在安装…")
    commands.device(["device", "install", "app", str(app), "--device", device_id], "install")
    status = {"deviceIdentifier": device_id, **identity, "installed": True,
              "previousDatabaseVerified": False, "launchSucceeded": False}
    write_json(run_directory / "installation.json", status)
    if before is not None:
        # Check the preserved store before the new executable can perform migrations.
        after = run_directory / "after-install"
        try:
            copy_from(commands, device_id, bundle, "Library/Application Support",
                      after / "Library/Application Support", "verify-preserved-store")
            if store_fingerprint(after) != before:
                raise InstallError("数据库内容与备份不一致。")
        except (InstallError, OSError, sqlite3.Error) as error:
            raise InstallError(f"安装已完成，但数据库保留检查未通过，未启动应用。"
                               f"请保留备份并查看：{run_directory}\n{error}") from error
        status["previousDatabaseVerified"] = True
        write_json(run_directory / "installation.json", status)
        say("原数据库保留检查通过。")
    say("4/4 正在打开 Schedule…")
    try:
        commands.device(["device", "process", "launch", "--device", device_id,
                         "--terminate-existing", bundle], "launch")
    except InstallError as error:
        say(f"应用已安装，但自动打开失败。请解锁手机后点开 Schedule；首次安装可能需要信任开发者。\n{error}")
        return False
    status["launchSucceeded"] = True
    write_json(run_directory / "installation.json", status)
    say("安装完成，Schedule 已打开。")
    return True


def verify_watch_relationship(app, phone_identity):
    watch_app = app / "Watch/ScheduleWatch.app"
    with (watch_app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    bundle = phone_identity["bundleIdentifier"]
    if (info.get("WKCompanionAppBundleIdentifier") != bundle
            or info.get("CFBundleIdentifier") != bundle + ".watchkitapp"):
        raise InstallError("手机与手表的应用标识不匹配，已停止安装。请使用 SCHEDULE_BUNDLE_IDENTIFIER 设置共同前缀。")
    return watch_app


def install_watch(commands, device, app, identity, run_directory):
    say("正在安装 Apple Watch 配套应用…")
    device_id = device["identifier"]
    try:
        commands.device(["device", "install", "app", str(app), "--device", device_id], "install-watch")
    except InstallError as error:
        raise InstallError(f"手机已安装，手表安装未完成；手机数据备份保留。\n{error}") from error
    status = {**identity, "installed": True, "launchSucceeded": False}
    report = run_directory / "watch-installation.json"
    write_json(report, status)
    try:
        commands.device(["device", "process", "launch", "--device", device_id,
                         "--terminate-existing", identity["bundleIdentifier"]], "launch-watch")
    except InstallError:
        say("手表应用已安装。请解锁手表后打开 Schedule，再在手机上打开 Schedule 完成首次同步。")
        return
    status["launchSucceeded"] = True
    write_json(report, status)
    say("手机和手表安装完成。两端打开 Schedule 后会同步当前学期。")


@contextmanager
def installer_lock():
    SUPPORT.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (SUPPORT / "install.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise InstallError("另一个安装任务正在进行，请等待它完成。")
        yield


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="一键构建、备份并覆盖安装 Schedule 到 iPhone/iPad。")
    parser.add_argument("device_id", nargs="?", help="兼容旧用法：设备标识")
    parser.add_argument("--device", default=os.environ.get("SCHEDULE_DEVICE_ID"),
                        help="设备名称、CoreDevice 标识或 UDID（多设备时使用）")
    parser.add_argument("--team", default=os.environ.get("SCHEDULE_TEAM_ID"),
                        help="签名 Team ID，默认读取本机 Signing.json，再沿用 Xcode 工程设置")
    destination = parser.add_mutually_exclusive_group()
    destination.add_argument("--watch", help="同时直接安装到指定 Apple Watch；默认读取本机 Signing.json 的 watchIdentifier")
    destination.add_argument("--phone-only", action="store_true", help="本次仅更新手机，忽略本机保存的手表目标")
    parser.add_argument("--list-devices", action="store_true", help="仅列出设备，不构建或安装")
    parser.add_argument("--build-dir", type=Path,
                        default=Path(os.environ.get("SCHEDULE_BUILD_DIR", str(BUILD))),
                        help="构建缓存目录")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    os.umask(0o077)
    if sys.platform != "darwin" or not shutil.which("xcodebuild"):
        say("需要 macOS 和完整的 Xcode（仅 Command Line Tools 不够）。")
        return 1
    try:
        with installer_lock():
            name = datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8]
            directory = SUPPORT / "Installations" / name
            directory.mkdir(parents=True, mode=0o700)
            commands = Commands(directory)
            commands.run(["xcrun", "--find", "devicectl"], "check-xcode")
            devices = commands.device(["list", "devices"], "list-devices")["devices"]
            if args.list_devices:
                for device in devices:
                    if device.get("hardwareProperties", {}).get("deviceType") in ("iPhone", "iPad", "appleWatch"):
                        say(describe(device))
                return 0
            selected = select_device(devices, args.device or args.device_id, sys.stdin.isatty())
            watch_id = None if args.phone_only else args.watch or configured_watch_identifier()
            watch = select_watch(devices, watch_id) if watch_id else None
            if watch and selected.get("hardwareProperties", {}).get("deviceType") != "iPhone":
                raise InstallError("Apple Watch 配套应用需要选择与手表配对的 iPhone。")
            if selected.get("deviceProperties", {}).get("developerModeStatus") == "disabled":
                raise InstallError("请在 iPhone 设置 → 隐私与安全性 → 开发者模式中开启开发者模式，然后重试。")
            if watch and watch.get("deviceProperties", {}).get("developerModeStatus") == "disabled":
                raise InstallError("请在 Apple Watch 设置 → 隐私与安全性中开启开发者模式，按提示重启并确认启用，再安装。")
            say(f"目标：{describe(selected)}\n备份和日志：{directory}")
            build_dir = args.build_dir.expanduser().resolve()
            team = configured_team(args.team)
            bundle_identifier = configured_bundle_identifier()
            build = ["xcodebuild", "-project", "Schedule.xcodeproj", "-scheme", "Schedule",
                     "-configuration", "Release", "-destination",
                     f"platform=iOS,id={selected['hardwareProperties']['udid']}",
                     "-destination-timeout", "30", "-derivedDataPath", str(build_dir),
                     "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration", "build"]
            if team:
                build.append(f"DEVELOPMENT_TEAM={team}")
            if bundle_identifier:
                build.append(f"SCHEDULE_BUNDLE_IDENTIFIER={bundle_identifier}")
            if watch:
                watch_build = list(build)
                watch_build[watch_build.index("-scheme") + 1] = "ScheduleWatch"
                watch_build[watch_build.index("-destination") + 1] = f"platform=watchOS,id={watch['hardwareProperties']['udid']}"
                say(f"正在准备手表签名：{describe(watch)}")
                commands.run(watch_build, "build-watch")
            say("1/4 正在构建并签名（首次较慢；后续复用编译缓存）…")
            commands.run(build, "build")
            app = build_dir / "Build/Products/Release-iphoneos/Schedule.app"
            identity = inspect_package(app, selected, commands)
            if bundle_identifier and identity["bundleIdentifier"] != bundle_identifier:
                raise InstallError("构建的应用标识与本机保存的标识不同，已停止以避免安装成另一个应用。")
            watch_app = verify_watch_relationship(app, identity)
            watch_identity = inspect_package(watch_app, watch, commands) if watch else None
            if watch_identity and watch_identity["teamIdentifier"] != identity["teamIdentifier"]:
                raise InstallError("手机与手表的签名团队不同，已停止安装。")
            update_app(commands, selected, app, identity, directory)
            if watch:
                install_watch(commands, watch, watch_app, watch_identity, directory)
            elif not args.phone_only:
                say("安装包已包含手表版。可在 iPhone 的 Watch 应用中安装 Schedule；直接安装可使用 --watch <标识>。")
        return 0
    except (InstallError, OSError, ValueError, KeyError, sqlite3.Error) as error:
        say(f"\n已停止：{error}\n不会卸载应用或清空手机数据。故障处理见 README 的本地部署部分。")
        return 1
    except KeyboardInterrupt:
        say("\n操作已中断；已有备份保留。若安装步骤已经开始，请先检查手机上的应用状态。")
        return 130


if __name__ == "__main__":
    sys.exit(main())
