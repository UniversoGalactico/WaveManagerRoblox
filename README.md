# WaveManager – Generic Wave Controller for Tower Defense & Survival Games
# Controlador de Oleadas Genérico para Tower Defense y Juegos de Supervivencia

🌐 **English** | **Español**

---

## 🇬🇧 English

A free, production‑ready wave management module for Roblox.  
Controls pre‑wave pauses, active wave loops, post‑wave rewards, and pause/resume functionality.

**What it offers:**
- **Pre‑wave countdown** – Gives players time to prepare before enemies spawn.
- **Active wave loop** – Tracks enemies remaining and wave duration, with automatic victory/defeat detection.
- **Post‑wave pause** – Cooldown between waves for rewards and preparation.
- **Pause/Resume** – Works with game pause systems (e.g., menus, cinematics).
- **Mutex‑based concurrency** – Prevents double wave starts and cleans up on player leave.
- **Circular log** – All events are recorded for audit and debugging.

**Dependencies:**
- `GuardUtils` (included in the Universo ecosystem)

**How to use:**
1. Place the `ModuleScript` in `ServerScriptService.ServerModules`.
2. Require it: `local WaveManager = require(script.Parent.WaveManager)`
3. Start a wave: `WaveManager.StartWave(player)`
4. Get wave state: `WaveManager.GetWaveState(player)`
5. Notify enemy killed: `WaveManager.OnEnemyKilled(enemyModel, player)`
6. Pause/Resume: `WaveManager.PauseWave(player)` / `WaveManager.ResumeWave(player)`

**Links:**
- **Talent Hub:** [More advanced modules](https://create.roblox.com/talent/creators/5075515911)
- **Discord:** universogalactico_28974 (UniversoGalactico)

---

## 🇪🇸 Español

Un módulo gratuito y listo para producción para gestionar oleadas en Roblox.  
Controla pausas pre‑oleada, bucles de oleada activa, recompensas post‑oleada y pausa/reanudación.

**Qué ofrece:**
- **Cuenta atrás pre‑oleada** – Da tiempo a los jugadores para prepararse.
- **Bucle de oleada activa** – Sigue los enemigos restantes y la duración, con detección automática de victoria/derrota.
- **Pausa post‑oleada** – Enfriamiento entre oleadas para recompensas y preparación.
- **Pausa/Reanudar** – Compatible con sistemas de pausa del juego (menús, cinemáticas).
- **Concurrencia con mutex** – Evita inicios dobles y limpia al salir el jugador.
- **Log circular** – Todos los eventos quedan registrados para auditoría y depuración.

**Dependencias:**
- `GuardUtils` (incluido en el ecosistema Universo)

**Cómo usarlo:**
1. Coloca el `ModuleScript` en `ServerScriptService.ServerModules`.
2. Requiérelo: `local WaveManager = require(script.Parent.WaveManager)`
3. Inicia una oleada: `WaveManager.StartWave(player)`
4. Obtén el estado: `WaveManager.GetWaveState(player)`
5. Notifica muerte de enemigo: `WaveManager.OnEnemyKilled(enemyModel, player)`
6. Pausa/Reanuda: `WaveManager.PauseWave(player)` / `WaveManager.ResumeWave(player)`

**Enlaces:**
- **Talent Hub:** [Módulos avanzados de pago](https://create.roblox.com/talent/creators/5075515911)
- **Discord:** universogalactico_28974 (UniversoGalactico)

---

*Made with ❤️ by Universogalactico64*
