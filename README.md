WaveManager
State-driven wave controller for Tower Defense and Survival genres. Decouples wave lifecycle from game logic.

API Reference:

WaveManager.StartWave(player: Player)
WaveManager.PauseWave(player: Player)
WaveManager.ResumeWave(player: Player)
WaveManager.OnEnemyKilled(enemy: Instance, player: Player)
WaveManager.GetWaveState(player: Player): {
    Status: "Countdown" | "Active" | "Paused" | "Intermission",
    CurrentWave: number,
    RemainingEnemies: number
}

Technical Specs:

State Engine: Mutex-protected state transitions prevent race conditions (double starts/skips).

Flow Control: Built-in hooks for pre-wave countdowns and post-wave cooldowns.

Auditing: Internal circular buffer tracks state history for debugging.

Dependency: Requires GuardUtils.

Lifecycle Diagram
Quick Start:

WaveManager.StartWave(player)

-- Integration hook
Enemy.Destroying:Connect(function()
    WaveManager.OnEnemyKilled(Enemy, player)
end)
