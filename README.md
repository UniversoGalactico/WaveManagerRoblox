# WaveManagerRoblox v2

A small, dependency-free, server-side wave controller for Roblox survival and tower-defense games. One controller represents one match, not one player.

> **v2.0.0-rc.3 — breaking API change.** The original singleton API is not compatible. Native Luau CI and Roblox Studio validation are release gates; the core regression suite has been executed locally under Lua 5.4.

## Install

Create a ModuleScript named `WaveManagerRoblox` in `ServerScriptService` and paste [WaveManagerRoblox.lua](WaveManagerRoblox.lua). No GuardUtils, RemoteEvents, services, or external packages are required.

## Quick start (deterministic example)

```lua
local WaveManager = require(game.ServerScriptService.WaveManagerRoblox)

local match = WaveManager.new({
    {count = 3, countdown = 5, duration = 30, intermission = 4},
    {count = 5, countdown = 5, duration = 45},
})

assert(match:start())
assert(match:step(5)) -- In a real match, pass elapsed time from Heartbeat.
local state = match:getState()
local token = state.token

-- Register each actual spawned enemy once, using a server-owned identity.
assert(match:registerEnemy(token, "enemy-1"))
assert(match:enemyKilled(token, "enemy-1"))
assert(match:getState().remainingEnemies == 2)
```

For an actual Roblox match, see [the NPC integration example](examples/RobloxMatch.server.lua). For a quick Studio check without assets, use [the smoke test](examples/StudioSmokeTest.server.lua).

## Lifecycle

```text
Idle -> Countdown -> Active -> Intermission -> Countdown -> ...
                     |                      (next wave)
                     +-> Completed (last wave resolved)
                     +-> Failed (timeout / fatal escape / external failure)

Countdown, Active and Intermission can be paused, resumed or cancelled.
```

Pause is a flag, not a separate phase. It freezes elapsed time and disallows new registrations. Death and escape notifications already in flight can still resolve registered enemies while paused; a final resolution preserves the pause into an intermission, unless the match has ended.

## API

| Method | Contract |
| --- | --- |
| `WaveManager.new(plan)` | Copy and validate a contiguous nonempty wave array. Throws for invalid configuration. |
| `match:start()` | Start once; immediately enter Active if the first countdown is zero. |
| `match:step(dt)` | Advance by finite, nonnegative elapsed seconds. Preserves time overshoot across countdown and intermission. No internal timers. |
| `match:pause()` / `match:resume()` | Freeze/resume time; repeated invalid transitions are rejected. |
| `match:registerEnemy(token, id)` | Register one identity for the current active wave. Reject duplicates, stale tokens and quota overflow. |
| `match:enemyKilled(token, id)` | Resolve a registered enemy as killed exactly once. |
| `match:enemyEscaped(token, id, fatal?)` | Resolve an escape exactly once. Optional boolean `true` fails the match atomically, even if this was the final enemy. |
| `match:cancel()` / `match:fail()` | End a live match immediately. Terminal states cannot restart. |
| `match:getState()` | Get a detached snapshot; the active token is an opaque identity. |
| `match:getHistory()` | Get detached copies of the latest 64 lifecycle/pause events in order. |

Mutating methods return `true` on acceptance or `false, reason` on rejection. A rejected command never advances the match. Create a new instance for a new match.

### Wave configuration

| Field | Default | Valid range |
| --- | --- | --- |
| `count` | Required | Integer 1–10,000 |
| `duration` | 60 seconds | 0.001–86,400 seconds |
| `countdown` | 10 seconds | 0–86,400 seconds |
| `intermission` | 15 seconds | 0–86,400 seconds |

The plan accepts 1–1,000 waves and only these four fields. The final wave has no intermission. A wave times out if it has not resolved every planned enemy. These are input bounds, not a Roblox NPC performance guarantee.

### State snapshot

- `phase`: Idle, Countdown, Active, Intermission, Completed, Failed or Cancelled
- `paused`, `wave` (0 before start), `waveCount`, `completedWaves`, `timeLeft`
- `totalEnemies`, `registeredEnemies`, `killedEnemies`, `escapedEnemies`, `resolvedEnemies`
- `remainingEnemies = totalEnemies - resolvedEnemies` (includes not-yet-spawned enemies)
- `unregisteredEnemies = totalEnemies - registeredEnemies`
- `aliveEnemies = registeredEnemies - resolvedEnemies` (last-wave accounting in terminal states, not a live Workspace query)
- `token`: non-nil only in Active; capture it at registration, never fetch a new token for a delayed event
- `reason`: nil until terminal, then timeout, fatal-escape, external, cancelled or all-waves-cleared

Enemy IDs can be nonempty strings (max 128 bytes), safe integers, tables, or userdata such as Instances. Each ID may be registered once per wave. Prefer small server-owned numeric/string IDs for very large waves: identity keys are retained until the wave finishes. IDs can be reused across waves only with the new token.

### Tower defense escapes

Compute the candidate damage without yielding; update base health only when the command succeeds:

```lua
local fatal = baseHealth <= damage
if match:enemyEscaped(capturedToken, enemyId, fatal) then
    baseHealth = math.max(0, baseHealth - damage)
end
```

A stale or duplicate notification cannot deal damage through this pattern. A fatal escape does not award a completed wave, even if remainingEnemies becomes zero.

## Integration rules

1. Keep the controller on the server. Do not expose the module's mutation methods or the raw token to clients.
2. One owner drives time. Call step with elapsed seconds from Heartbeat, or synchronize a monotonic clock before each event for tighter deadline ordering. Do not combine both drivers.
3. Register an enemy before it becomes active. Capture its exact token; check method return values.
4. Use a real death event, e.g. Humanoid.Died. Destroying a model does not necessarily mean it was killed. Use enemyEscaped for escapes, and fail/cancel for external termination.
5. Detect new waves by token, not just phase: zero countdown and intermission can transition directly from Active to Active in the same call.
6. Spawn, despawn, movement, rewards, player lifecycle, networking and UI belong to the caller. Cancel and clean up when the owner removes a live match.
7. Core calls do not yield or invoke callbacks. Use a single serial execution context; this is not cross-Actor synchronization. A timeout processed before a death wins by definition. Fractional seconds use floating-point arithmetic.

## Migration from v1

| v1 | v2 |
| --- | --- |
| StartWave(player) | WaveManager.new(plan), then match:start() |
| PauseWave(player) / ResumeWave(player) | match:pause() / match:resume() |
| OnEnemyKilled(enemy, player) | match:registerEnemy(token, enemy), then match:enemyKilled(token, enemy) |
| GetWaveState(player) | match:getState() |
| CancelWave(player) | match:cancel() |

Player-to-match mappings now belong to your game. Multiple players can share one match controller.

## Reproduce tests

```sh
luau tests/run.lua
python3 tests/mutation.py --runner luau
# Or use Lua 5.4 as a portable fallback:
lua5.4 tests/run.lua
python3 tests/mutation.py --runner lua5.4
```

The local Lua 5.4 run for rc.3 passed 2,732,757 assertions, including 157,961 model-checked randomized operations, 500 success-biased campaigns, a 1,000-wave run and a 10,000-enemy wave. The mutation audit detected all 28 intentional regressions. These checks are not a proof of correctness, a native Luau result, or an NPC throughput benchmark.

## License

MIT; see [LICENSE](LICENSE).
