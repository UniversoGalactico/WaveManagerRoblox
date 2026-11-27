# WaveManager v2 technical audit — 2026-11-27

## Verdict

The original controller needed replacement, not incremental cosmetic repair. Version 2.0.0 is suitable for release within the documented scope, following native CI and owner-reported real Studio stress validation. It is not an unconditional production certification. Version 1 callers must migrate explicitly.

## Original defects and design decisions

| Defect | Replacement |
| --- | --- |
| Blocking task.wait lifecycle, implicit singleton | Per-match controller; caller supplies elapsed time; no background work |
| Wave index fixed at one | Validated copied plan; ordered transitions and monotonic completed count |
| Pause could terminate the loop or consume wall time | Pause flag freezes the logical clock; explicit in-flight event contract |
| Duplicate, foreign or unregistered kills could decrement counters | Register once per wave; resolve exactly once; reject stale generation token |
| Destroying conflated deletion with death | Integration uses Humanoid.Died; escape and cancellation are separate |
| GuardUtils mutex dependency and shared mutable state | Dependency-free serial state transitions, without a global registry |
| Coarse timing and no safe ownership contract | Compensated subtraction, finite input validation, opaque token and detached snapshots |

A fatal escape overrides wave completion even when it resolves the last enemy. No event is accepted after a terminal state. New matches require new instances; there is no implicit restart. Zero countdown and intermission are supported. A positive time step treats a remaining residue at or below 1 ns as elapsed.

## Invariants reviewed

- Within a wave: 0 <= resolved <= registered <= total, and resolved = killed + escaped.
- Remaining = total - resolved; alive = registered - resolved.
- Active phase has exactly one unique token; non-Active phases have none. A delayed token from another wave or match cannot authorize an event.
- completedWaves never decreases; a fatal escape does not increment it.
- Rejected commands leave logical state unchanged; external callbacks and yields are absent from core transitions.
- Time cannot advance during pause. A final in-flight resolution may move to paused intermission.
- Terminal states are absorbing and release stored enemy identities.
- Configuration is copied and restricted to a contiguous array of 1–1,000 waves and finite validated values.
- History is a chronological 64-entry lifecycle ring, not an unbounded per-enemy event log.

These are the intended contracts; the tests exercise them over defined inputs and do not constitute a mathematical proof for every possible runtime interaction.

## Iterations

The refactor progressed from lifecycle isolation, through validated transitions and terminal semantics, to fractional-timing compensation and mutation-based validation. The final rc.5 revision removed a global weak-key state registry: a value referring indirectly to its controller key can be retained by a weak-key registry under Luau's collector semantics. Bound private methods instead keep ownership in an unreachable collectable object graph.

This design costs memory and dispatch overhead per controller. A local synthetic Lua 5.4 comparison at 10,000 controllers observed approximately 14.1 MiB live memory with the rc.4 design versus 31.5 MiB with rc.5, and approximately 0.306 s versus 0.415 s for one million step calls. These are environment-specific measurements, not Roblox benchmarks. In the same experiment, the global registry left about 385 KiB allocated after collection, while rc.5 left about 0.2 KiB. The design prioritizes isolated ownership rather than claiming a speed improvement.

## Reproducible evidence

| Check | Result |
| --- | --- |
| Native Luau 0.748 regression suite | 2,732,797 counted assertions; 157,961 randomized operations; 500 successful campaigns |
| Bounded exhaustive exploration | 128 plans; 30,528 abstract states; 885,312 commands (96,832 accepted; 788,480 rejected) |
| Native mutation audit | 33/33 deliberately introduced regressions detected |
| Synthetic capacity | 1,000 sequential waves; one wave with 10,000 distinct enemy identities |
| Portable Lua 5.4 regression | 2,732,800 counted assertions, including forced GC checks |
| Lua mock integration | 12/12 scenarios, including delayed events, lag spike, fatal setup errors and teardown |
| Fractional clock (native Luau and local Lua 5.4) | 360,605 steps against integer-microsecond reference; 40,199 pauses |
| Long timer (native Luau and local Lua 5.4) | 5,184,000 simulated 60 Hz frames (24 hours of logical time) |
| Resource release (portable Lua 5.4 CI) | 7 GC scenarios; 1,000 abandoned cyclic controllers collected |
| Match isolation (native Luau and local Lua 5.4) | 256 interleaved matches, 5,120 waves, 61,184 commands |
| Generated configuration (native Luau and local Lua 5.4) | 20,000 plans: 4,982 valid copied, 15,018 invalid rejected |

Native and portable regression/mutation/mock CI evidence: [run 46081949237](https://github.com/UniversoGalactico/WaveManagerRoblox/actions/runs/46081949237), commit 85353af677eff99b1a625c5ef08b739bd86fa86d. Numeric and GC checks subsequently passed in [run 46082099940](https://github.com/UniversoGalactico/WaveManagerRoblox/actions/runs/46082099940). All 33 mutant sources were also independently compiled under Lua 5.4 to exclude syntax-only failures. All 11 code/test/example file blob IDs were checked against the locally tested copies; the full expanded suite passed in [run 46082266870](https://github.com/UniversoGalactico/WaveManagerRoblox/actions/runs/46082266870), commit 123ba40700ae39d0a21e865b749c88606ef179cf. The stable promotion changes only the core version string; local automated runs used Lua 5.4, not Roblox. Separate real Studio results are documented below.

## Complexity and boundaries

Construction copies O(waves) configuration. Registration and resolution have expected constant-time table operations; a time step crosses at most intermission, countdown and one active deadline. Snapshot generation is constant-size; history copies at most 64 entries. Retained identities are bounded by the current wave quota. Tables or Instances remain referenced through wave end to reject duplicate notifications; scalar IDs reduce retention. This is not a memory bound on arbitrary objects reachable from supplied identities.

Core methods do not yield, start tasks, invoke callbacks or use global Roblox services. They are designed for one serial server context, not concurrent Parallel Luau Actors. The private state design is not a security sandbox against trusted server code using raw operations. Treat clients as untrusted and never accept their tokens or kill claims directly.

## Roblox Studio validation (2026-11-27)

The repository owner reported PASS for the asset-free smoke test and the final Studio stress suite. The supplied log independently records 42/42 moving Humanoid rigs (minimum displacement 9.22 studs), 64 simultaneous Humanoid deaths, and PASS for cases 01–13. The final v3 run was reported as all PASS; its full output was not supplied. The Studio suite skips deliberately thrown exceptions by default to avoid debugger interruptions; those cases passed native CI. The tested rc.5 module has blob ID c503ef19828722c27ca41ff1d932f1cfabffdc97. The stable module differs only in version metadata. See [validation record](docs/STUDIO_VALIDATION.md).

## Remaining limitations

1. Profile real multiplayer servers with representative NPC AI, physics and network load. Synthetic IDs do not measure server FPS or NPC throughput.
2. Integrate explicit owner-driven teardown; a script's own Destroying signal is best-effort under deferred engine events. The example is not independently certified for every integration.
3. Migrate v1 callers explicitly. This is an orchestration core, not an NPC AI/spawner, matchmaking system, base health manager, reward service or replication layer.

No claim is made that every possible Roblox integration is correct.
