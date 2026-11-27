# Roblox Studio validation — 2026-11-27

## Evidence and scope

- The repository owner reported PASS for the asset-free smoke test.
- The supplied Studio output for the v2 stress package records PASS for cases 01–13, including 42/42 moving Humanoids over three waves (6, 12, 24; minimum displacement 9.22 studs), 64 Humanoids dying in one frame, delayed/duplicate events, pause, cross-match isolation, cancellation, exact timeout, escape and cleanup.
- The first two stress packages stopped in case 14 when the debugger intercepted a deliberately thrown, pcall-protected ownership error. This was not evidence of an unexpected core failure.
- The owner subsequently reported all PASS for the v3 stress package. Full final logs were not supplied. V3 defaults to skipping intentional throwing cases in Studio; native Luau CI still covers those cases.
- Studio package: WaveManager_NPC_Stress_v3.rbxmx, SHA-256 cf38b0994f255c1a7bf1942ee0d39f5d4598c0f4640e141a97c4dc9989261483.
- The module extracted from that package has Git blob SHA c503ef19828722c27ca41ff1d932f1cfabffdc97 (rc.5). Stable 2.0.0 only changes its version metadata.

## Automated evidence

[Complete native Luau 0.748 and portable Lua 5.4 CI](https://github.com/UniversoGalactico/WaveManagerRoblox/actions/runs/46082266870) passed regression, exhaustive exploration, mutation, numeric, configuration, isolation, mock integration and resource tests.

## Limits

The Studio result is a developer-reported integration check, not an independent certification, live-server benchmark or guarantee of every game integration. Actual NPC performance depends on AI, physics, networking and the game. The module's input quota is not a claim that Roblox can simulate that many NPCs.
