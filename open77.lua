resource "opx_needs"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true

-- OPX//77 needs: hunger and thirst go down over time, hurt at zero, and eating / drinking plays an animated
-- timed action (opx_progress through opx_core's `progress` provider). The values are opx_core character
-- metadata (`hunger`, `thirst`): opx_core saves them and the HUD provider draws them. No table of its own.
-- The inventory, the progress bar and the medical resource are optional providers (never named here).
dependency "opx_core"

permissions {
    "network.events",       -- both: the consume request and its answer, notifications
    "players.stats.apply",  -- server: Open77.players.damage (starving)
    "players.damage.apply", -- older spelling of players.stats.apply, still checked by some builds
    "players.stats.read",   -- server: Open77.stats.getHealth (health floor when starving is not lethal)
    "players.life.read",    -- server: Open77.players.isDead (no decay / damage while dead)
}

shared_script "config.lua"

-- No `require` on the server: the files share the global table Needs, loaded in this order.
server_scripts {
    "server/needs.lua",
    "server/consume.lua",
    "server/main.lua",
}

client_script "client/main.lua"

files {
    "locales/*.json",
}
