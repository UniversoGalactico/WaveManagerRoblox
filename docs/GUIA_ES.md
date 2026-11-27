# Guía rápida de WaveManager v2 en Roblox Studio

## 1. Probar el módulo sin assets

1. En ServerScriptService, crea un ModuleScript llamado WaveManagerRoblox.
2. Copia el contenido de [WaveManagerRoblox.lua](../WaveManagerRoblox.lua).
3. Junto a él crea un Script y copia [StudioSmokeTest.server.lua](../examples/StudioSmokeTest.server.lua).
4. Inicia Play. En Output debe aparecer WaveManager Studio smoke test: PASS.
5. Elimina o desactiva el script de prueba cuando termines.

Esto comprueba una campaña de dos oleadas, pausa, muertes duplicadas, escapes y rechazo de tokens anteriores usando Instances reales. Las pruebas de CI no sustituyen este paso.

## 2. Usarlo en un juego

```lua
local W = require(game.ServerScriptService.WaveManagerRoblox)
local match = W.new({
    {count = 5, countdown = 3, duration = 30, intermission = 5},
    {count = 10, countdown = 3, duration = 45},
})
assert(match:start())
```

El dueño de la partida debe llamar a match:step(dt) con el tiempo transcurrido. El módulo no crea enemigos ni usa Heartbeat por su cuenta.

Cuando getState().phase sea Active, captura getState().token y registra cada enemigo real con match:registerEnemy(token, enemyId). Si devuelve false, no lo añadas al juego como enemigo de esa oleada.

Al morir, llama match:enemyKilled(token, enemyId). Conserva el token original en el callback: nunca lo sustituyas por el token de una oleada nueva.

Para una salida de enemigos de tower defense, usa match:enemyEscaped(token, enemyId, fatal). Solo aplica daño a la base si devuelve true. Si fatal es true, la partida termina como Failed incluso si era el último enemigo.

## 3. Ejemplo con NPC reales

Crea un Model EnemyTemplate con Humanoid vivo en ServerStorage y un BasePart EnemySpawn en Workspace. Copia [RobloxMatch.server.lua](../examples/RobloxMatch.server.lua) como Script junto al ModuleScript. Este ejemplo genera NPC a intervalos y escucha Humanoid.Died; no incluye IA, daño ni movimiento.

## 4. Decisiones importantes

- Una instancia representa una partida, no un jugador.
- Una partida terminal no se reinicia: crea otro controlador.
- La pausa congela tiempo y nuevas apariciones; las notificaciones de muerte ya en vuelo pueden resolverse. Tu juego debe pausar también su IA, movimiento y demás sistemas si lo necesita.
- El servidor controla la identidad de enemigos y sus resultados; jamás confíes en una solicitud de muerte del cliente.
- Al abandonar una arena, cancela la partida y desconecta sus conexiones explícitamente.
- Los límites de 1.000 oleadas y 10.000 identificadores no garantizan que Roblox pueda simular 10.000 NPC.

La API completa está en [README](../README.md). El [informe técnico](../AUDIT.md) explica las pruebas y limitaciones. La v2 no es compatible directamente con las llamadas de v1.
