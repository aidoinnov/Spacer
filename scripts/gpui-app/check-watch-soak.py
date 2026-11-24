#!/usr/bin/env python3
"""Timed production watch gate on an owned process and disposable fixture only.

Runs on macOS/Windows with Python and the packaged control transport. Never
attaches to an existing analysis, changes file associations, or empties Trash.
The requested duration is a bounded observation, not a production guarantee.
"""
import argparse
import contextlib
import hashlib
import json
import pathlib
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
import uuid

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "mcp"))
from space_sniffer_mcp import Bridge


@contextlib.contextmanager
def inherited_fixture():
    # Python's Windows mode-0700 temporary directory can exclude the limited
    # interactive token when the SSH owner is elevated. Inherit the user's Temp
    # ACL instead; never change permissions on an existing directory.
    directory = pathlib.Path(tempfile.gettempdir()) / ("sniffer-owned-watch-soak-" + uuid.uuid4().hex)
    directory.mkdir(mode=0o755)
    try:
        yield str(directory)
    finally:
        shutil.rmtree(directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=pathlib.Path)
    parser.add_argument("--seconds", type=int, default=900)
    parser.add_argument("--bundle-id", default="local.macspacesniffer.app")
    parser.add_argument("--instance", type=int, help="Reuse an explicitly owned, single idle window; avoids launching/focusing another GUI")
    parser.add_argument("--replace-owned-root", type=pathlib.Path, help="Exact existing disposable root allowed in the owned window, instead of idle")
    parser.add_argument("--background-qa", action="store_true", help="Use a QA-feature binary without showing or focusing a window; production rejects this flag")
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    assert 30 <= args.seconds <= 86400
    assert not args.output.exists(), "Use a fresh output path"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bridge = Bridge(args.bundle_id)
    report = {"passed": False, "requestedSeconds": args.seconds,
              "harnessSHA256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
              "backgroundQA": args.background_qa,
              "binarySHA256": hashlib.sha256(args.binary.read_bytes()).hexdigest(),
              "platform": sys.platform, "rounds": 0, "operations": 0, "hiddenPaints": 0}
    samples = []
    convergence = []
    child = None
    with inherited_fixture() as directory:
        root = pathlib.Path(directory) / "input"
        for i in range(32):
            (root / f"branch-{i:02d}" / "nested").mkdir(parents=True)
        with args.output.with_suffix(".app.log").open("w") as log:
            try:
                if args.instance:
                    pid = args.instance
                    initial = bridge.call_app("app_status", {"instance_id": pid})
                    assert len(initial["windows"]) == 1, "Refusing an instance with other windows"
                    state = initial["windows"][0]
                    matched = args.replace_owned_root and state["root"] and os.path.normcase(os.path.normpath(state["root"])) == os.path.normcase(str(args.replace_owned_root))
                    assert state["phase"] == "idle" or matched, "Refusing to replace an unapproved document"
                    report["attachedToOwnedWindow"] = True
                else:
                    launch = [str(args.binary.resolve()), "--scan", str(root)]
                    if args.background_qa:
                        launch.append("--qa-background")
                    child = subprocess.Popen(launch,
                                             stdout=log, stderr=subprocess.STDOUT)
                    pid = child.pid
                report["ownedPid"] = pid

                def call(command, **values):
                    assert child is None or child.poll() is None, "Owned GUI exited early"
                    return bridge.call_app(command, dict(instance_id=pid, **values))

                deadline = time.monotonic() + 30
                while not any(i["pid"] == pid for i in bridge.instances()):
                    assert child is None or child.poll() is None, "Owned GUI failed to launch"
                    assert time.monotonic() < deadline, "No owned controller"
                    time.sleep(.1)
                if args.instance:
                    call("scan_start", path=str(root), watching=True)

                def converge(watching=True):
                    files = [p for p in root.rglob("*") if p.is_file()]
                    expected = (len(files), sum(p.stat().st_size for p in files), 1 + sum(p.is_dir() for p in root.rglob("*")))
                    started = time.monotonic()
                    if args.background_qa:
                        call("view_capture")
                        report["hiddenPaints"] += 1
                    while time.monotonic() - started < 25:
                        state = call("app_status")["windows"][0]
                        actual = (state["files"], state["snapshot_logical_bytes"], state["folders"])
                        if args.background_qa:
                            assert not state["window_visible"], "Background QA unexpectedly showed its window"
                            if state["projection_pending"] or state["geometry_pending"]:
                                call("view_capture")  # Paint only the hidden GPUI surface, no OS input.
                                report["hiddenPaints"] += 1
                        if state["phase"] == "completed" and not state["projection_pending"] and not state["geometry_pending"] and actual == expected and state["watch_active"] == watching:
                            assert not state["error"] and state["issue_count"] == 0, state
                            convergence.append(round((time.monotonic() - started) * 1000, 3))
                            return state
                        time.sleep(.1)
                    raise AssertionError({"expected": expected, "actual": state})

                converge()
                # Previously scan_start silently ignored both documented options.
                call("scan_start", path=str(root), watching=False, include_mounted_volumes=True)
                stopped = converge(watching=False)
                assert stopped["volume_traversal"] == "allVolumes", stopped
                call("scan_start", path=str(root), watching=True, include_mounted_volumes=False)
                restarted = converge()
                assert restarted["volume_traversal"] == "selectedVolume", restarted
                report["scanStartOptionsApplied"] = True
                # Navigation addresses the canonical snapshot spelling, including
                # Windows Temp aliases/case returned by the native engine.
                root = pathlib.Path(restarted["root"])
                started = time.monotonic()
                with args.output.with_suffix(".samples.jsonl").open("w") as stream:
                    while time.monotonic() - started < args.seconds:
                        n = report["rounds"]
                        for i in range(32):
                            folder = root / f"branch-{i:02d}"
                            source = folder / "write.tmp"
                            target = folder / "nested" / "current.bin"
                            source.write_bytes(bytes([(i + n) % 256]) * ((n % 7 + 1) * (i + 1)))
                            source.replace(target)
                            report["operations"] += 2
                        converge()  # Do not let deletion obscure missed creates/renames.
                        for i in range(32):
                            target = root / f"branch-{i:02d}" / "nested" / "current.bin"
                            if (i + n) % 3 == 0:
                                target.unlink()
                                report["operations"] += 1
                            elif i % 4 == 0:
                                target.write_bytes(b"rewrite" * (n % 11 + 1))
                                report["operations"] += 1
                        state = converge()
                        if n % 12 == 0:
                            call("view_set", path=str(root / "branch-00" / "nested"), list_mode=False, expression="")
                        elif n % 12 == 3:
                            call("view_set", list_mode=True)
                        elif n % 12 == 6:
                            call("view_set", action="root", list_mode=False, expression="*.sniffer-never-match")
                        elif n % 12 == 9:
                            call("view_set", action="root", list_mode=False, expression="")
                        if n % 12 in (0, 3, 6, 9):
                            state = converge()
                            expected_focus = root / "branch-00" / "nested" if n % 12 in (0, 3) else root
                            assert pathlib.Path(state["focus_path"]).resolve() == expected_focus.resolve(), state
                        resources = call("app_resources")
                        for worker in resources["workers"]:
                            for kind in ("projection", "geometry"):
                                assert worker[kind]["peak_active"] <= 1, worker
                                assert worker[kind]["pending"] <= 1, worker
                        sample = {"seconds": round(time.monotonic() - started, 3),
                                  "files": state["files"], "bytes": state["snapshot_logical_bytes"],
                                  "focus": state["focus_path"], "listMode": state["list_mode"],
                                  "filter": state["filter"], "windowVisible": state["window_visible"],
                                  "revision": state["snapshot_revision"], "resources": resources}
                        samples.append(sample)
                        stream.write(json.dumps(sample) + "\n")
                        stream.flush()
                        report["rounds"] += 1
                        time.sleep(.5)
                report["durationSeconds"] = round(time.monotonic() - started, 3)
                # Disable root watch before creation: this branch is provably
                # absent from its cache, so navigation must park the original.
                call("view_set", action="root", expression="", list_mode=False)
                converge()
                call("view_set", watching=False)
                converge(watching=False)
                branch = root / "newly-added-branch"
                branch.mkdir()
                call("view_set", path=str(branch))

                def parked_state():
                    if args.background_qa:
                        call("view_capture")
                        report["hiddenPaints"] += 1
                    value = call("app_status")["windows"][0]
                    assert not args.background_qa or not value["window_visible"], value
                    assert pathlib.Path(value["root"]).resolve() == branch.resolve(), value
                    return value

                deadline = time.monotonic() + 25
                while True:
                    state = parked_state()
                    if state["phase"] == "completed" and not state["projection_pending"] and not state["geometry_pending"]:
                        break
                    assert time.monotonic() < deadline, state
                    time.sleep(.1)
                report["parkedDocumentConfirmed"] = True
                call("view_set", watching=True)  # The original parked root owns watch.
                # The branch was intentionally created while watch was disabled.
                # Explicitly establish the baseline before testing NEW watch events;
                # enabling a watcher does not promise replay of missed OS events.
                baseline = call("scan_rescan")
                assert baseline["background"], baseline
                deadline = time.monotonic() + 25
                while True:
                    state = parked_state()
                    owner = next(d for d in state["scan_documents"] if pathlib.Path(d["document_root"]).resolve() == root.resolve())
                    if not owner["scanning"] and owner["version"] != baseline["previous_version"]:
                        assert owner["folders"] == 1 + sum(p.is_dir() for p in root.rglob("*")), owner
                        break
                    assert time.monotonic() < deadline, owner
                    time.sleep(.1)
                report["parkedWatchBaselineRescan"] = True
                for n in range(12):
                    before = next(d for d in parked_state()["scan_documents"] if pathlib.Path(d["document_root"]).resolve() == root.resolve())
                    (root / "branch-31" / "parked-root-event.txt").write_text(f"owned parked root update {n}")
                    deadline = time.monotonic() + 25
                    while True:
                        state = parked_state()
                        owner = next(d for d in state["scan_documents"] if pathlib.Path(d["document_root"]).resolve() == root.resolve())
                        if not owner["scanning"] and owner["version"] != before["version"]:
                            assert not owner["offline"] and not owner["cancelled"] and owner["issues"] == 0, owner
                            break
                        assert time.monotonic() < deadline, owner
                        time.sleep(.1)
                report["confirmedParkedWatchUpdates"] = 12
                call("view_set", action="root")
                restored = converge()
                assert pathlib.Path(restored["root"]).resolve() == root.resolve(), restored
                report["parkedRootWatchChecks"] = 12
                call("view_set", watching=False)
                deadline = time.monotonic() + 10
                while call("app_status")["windows"][0]["watch_active"]:
                    assert time.monotonic() < deadline, "Watch did not stop"
                    time.sleep(.1)
                state = call("app_status")["windows"][0]
                revision = state["snapshot_revision"]
                (root / "after-watch-stop.txt").write_text("not watched")
                time.sleep(2)
                assert call("app_status")["windows"][0]["snapshot_revision"] == revision, "Stopped watch still publishes"
                call("window_close", window_id=state["window_id"])
                close_started = time.monotonic()
                if child:
                    child.wait(timeout=8)
                    assert child.returncode == 0, f"Owned GUI exited abnormally: {child.returncode}"
                else:
                    deadline = time.monotonic() + 8
                    while any(i["pid"] == pid for i in bridge.instances()):
                        assert time.monotonic() < deadline, "Owned attached GUI did not close"
                        time.sleep(.05)
                report.update(passed=True, guiExitCode=child.returncode if child else None, closeMs=round((time.monotonic() - close_started) * 1000, 3),
                              watchStopped=True, samples=len(samples),
                              rssFirstBytes=samples[0]["resources"]["process"]["rss_bytes"],
                              rssLastBytes=samples[-1]["resources"]["process"]["rss_bytes"],
                              rssMaxBytes=max(s["resources"]["process"]["rss_bytes"] for s in samples),
                              convergenceMedianMs=statistics.median(convergence),
                              convergenceMaxMs=max(convergence), exactOracleChecks=len(convergence),
                              scope="Timed live filesystem create/replace/cross-directory rename/rewrite/delete; exact files/bytes/folders after each phase; bounded latest workers; stopped watch; owned process close. Not a scan throughput or disktree comparison.")
            except BaseException as error:
                report["error"] = repr(error)
                raise
            finally:
                if child and child.poll() is None:
                    child.terminate()
                    try:
                        child.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        report["forcedTermination"] = True
                args.output.write_text(json.dumps(report, indent=2) + "\n")
    report["ownedFixtureRemoved"] = not pathlib.Path(directory).exists()
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
