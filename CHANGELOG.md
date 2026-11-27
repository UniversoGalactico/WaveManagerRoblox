# WaveManagerRoblox 2.0.0

Stable major rewrite of the server-side wave controller for Roblox survival and tower defense.

## Highlights

- One isolated controller per match, including cooperative matches.
- Explicit countdown, active, intermission and terminal states.
- Dependency-free, non-yielding core with deterministic elapsed-time stepping.
- Correct pause/resume, cancellation, timeout and campaign progression.
- Unique wave tokens; duplicate, foreign and stale enemy notifications rejected.
- Kills, escapes and atomic fatal escapes.
- Compensated fractional timing, validated copied plans and bounded lifecycle history.
- MIT license, English API documentation, Spanish quickstart, Studio example and automated tests.

## Validation

Native Luau CI passed 2,732,797 counted assertions, 157,961 model-checked random operations, 885,312 bounded exhaustive commands, 33/33 deliberate mutations, 20,000 configurations and 256 interleaved matches. The repository owner reported passing the Studio stress suite; the supplied intermediate logs confirm 42 moving NPCs and a 64-Humanoid death burst. See AUDIT.md and docs/STUDIO_VALIDATION.md for scope, including intentional exception cases covered by CI instead of the default Studio harness.

## Migration

**Breaking change:** v1 singleton methods are replaced with WaveManager.new(plan) and instance methods. See README.md. Install the attached WaveManagerRoblox.lua as a ModuleScript in ServerScriptService. No GuardUtils required.

This is a wave orchestration core, not an NPC AI, spawning, networking or rewards framework. Profile real game loads before deployment.
