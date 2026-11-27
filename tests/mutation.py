"""Behavioral mutation audit: every deliberate regression must be detected.

Usage: python3 tests/mutation.py --runner luau
       python3 tests/mutation.py --runner lua5.4
"""
import argparse
from pathlib import Path
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "WaveManagerRoblox.lua").read_text()
SUITE = (ROOT / "tests/run.lua").read_text()

# name, exact source fragment, replacement, occurrence (1-based)
MUTANTS = [
    ("repeat start", '    if s.phase ~= "Idle" then return false, "already-started" end\n', '', 1),
    ("paused step reports success", '    if s.paused then return false, "paused" end\n', '', 1),
    ("paused registration", '    if s.paused then return false, "paused" end\n', '', 2),
    ("discard overshoot", '        dt = dt - s.timeLeft', '        dt = 0', 1),
    ("timeout wins", 'terminal(s, "Failed", "timeout")', 'terminal(s, "Completed", "timeout")', 1),
    ("alias caller plan", '    return result\nend\n\nlocal function get', '    return plan\nend\n\nlocal function get', 1),
    ("stale registration", '    if not rawequal(token, s.token) then return false, "stale-token" end\n', '', 1),
    ("stale resolution", '    if not rawequal(token, s.token) then return false, "stale-token" end\n', '', 2),
    ("duplicate registration", '    if s.enemies[id] ~= nil then return false, "duplicate-enemy" end\n', '', 1),
    ("quota overflow", '    if s.registered >= s.total then return false, "quota-full" end\n', '', 1),
    ("duplicate resolution", '    if s.enemies[id] ~= true then', '    if s.enemies[id] == nil then', 1),
    ("unregistered resolution", '    if s.enemies[id] ~= true then', '    if s.enemies[id] == false then', 1),
    ("fatal escape ignored", '    if fatal then\n', '    if false then\n', 1),
    ("truthy fatal flag", '    if fatal ~= nil and type(fatal) ~= "boolean" then return false, "invalid-fatal" end\n', '', 1),
    ("escape counted as kill", '        s.escaped = s.escaped + 1', '        s.killed = s.killed + 1', 1),
    ("skip intermission", 'enter(s, "Intermission", s.plan[s.wave].intermission)', 'enter(s, "Intermission", 0)', 1),
    ("unbounded log", '1000, 10000, 64', '1000, 10000, 100000', 1),
    ("retain old token", '    s.token = nil\n', '', 1),
    ("invalid dt accepted", '    if not finite(dt) or dt < 0 then return false, "invalid-dt" end\n', '', 1),
    ("unknown plan keys", '            assert(key == "count" or key == "duration" or key == "countdown" or key == "intermission",\n                "Unknown field in wave " .. i)', '            assert(true)', 1),
    ("terminal stays paused", '    s.reason, s.paused = reason, false', '    s.reason = reason', 1),
    ("drop deaths while paused", 'local function resolveEnemy(s, token, id, outcome, fatal)\n', 'local function resolveEnemy(s, token, id, outcome, fatal)\n    if s.paused then return false end\n', 1),
    ("resume leaves expired phase", '    record(s, "Resumed")\n    advance(s, 0)', '    record(s, "Resumed")', 1),
    ("incorrect completed counter", 's.completedWaves = s.completedWaves + 1', 's.completedWaves = s.completedWaves + 2', 1),
    ("wrong external failure", 'terminal(s, "Failed", "external")', 'terminal(s, "Cancelled", "external")', 1),
    ("missing countdown", 'enter(s, "Countdown", w.countdown)', 'enter(s, "Countdown", 0)', 1),
    ("history aliases internal log", '        result[#result + 1] = {\n            sequence = event.sequence, event = event.event, wave = event.wave,\n            phase = event.phase, paused = event.paused, reason = event.reason,\n        }', '        result[#result + 1] = event', 1),
    ("repeat enemy after resolution", '    s.enemies[id] = false', '    s.enemies[id] = nil', 1),
]


def mutate(source, old, new, nth):
    start = -1
    for _ in range(nth):
        start = source.find(old, start + 1)
        if start < 0:
            raise ValueError(f"mutation target not found: {old!r}")
    return source[:start] + new + source[start + len(old):]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", default="luau")
    args = parser.parse_args()
    runner = shlex.split(args.runner)
    with tempfile.TemporaryDirectory(prefix="wave-mutation-") as directory:
        root = Path(directory)
        (root / "tests").mkdir()
        (root / "tests/run.lua").write_text(SUITE)
        module = root / "WaveManagerRoblox.lua"

        def run(source):
            module.write_text(source)
            try:
                result = subprocess.run([*runner, "tests/run.lua"], cwd=root,
                                        capture_output=True, text=True, timeout=15)
                return result.returncode, result.stdout + result.stderr
            except subprocess.TimeoutExpired:
                return None, "timeout"

        status, output = run(SOURCE)
        if status != 0:
            raise SystemExit("Baseline failed:\n" + output)
        print(output.strip())
        survivors = []
        for name, old, new, nth in MUTANTS:
            status, output = run(mutate(SOURCE, old, new, nth))
            if status == 0:
                survivors.append(name)
                print("SURVIVED:", name)
            elif status is None:
                # Do not count hangs as detected assertions.
                survivors.append(name + " (timeout)")
                print("INCONCLUSIVE:", name, "(timeout)")
            else:
                print("DETECTED:", name)
        print(f"Mutation audit: {len(MUTANTS) - len(survivors)}/{len(MUTANTS)} detected")
        if survivors:
            raise SystemExit("Undetected regressions: " + ", ".join(survivors))


if __name__ == "__main__":
    main()
