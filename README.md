# Simple Waypoints

A minetest 5.2.0+ mod that lets you set waypoints/beacons at current position.

![beacon](img/screenie1.png) ![waypoints GUI](img/screenie2.png)

#### How it works
This mod offers two ways to manage your waypoints: a text-based interface using chat commands and a graphical user interface (GUI). Choose the method that you find most convenient.


TEXT INTERFACE:

- **Create Waypoint:** `/wc <waypoint name>`
- **Delete Waypoint:** `/wd <waypoint name>`
- **Teleport to Waypoint:** `/wt <waypoint name>`
- **List Waypoints:** `/wl`
- **Toggle HUD Display:** `/sw_hud <on|off|toggle|status>` - Show or hide waypoint markers in HUD
- **Toggle Beacons:** `/sw_beacons <on|off|toggle|status>` - Enable or disable beacon nodes in the world

GUI:
- **Use menu:** `/wf`

#### Toggle Commands

The `/sw_hud` and `/sw_beacons` commands allow you to dynamically control waypoint visibility:

- **`/sw_hud on`** - Enable waypoint HUD markers for all players
- **`/sw_hud off`** - Disable waypoint HUD markers for all players
- **`/sw_hud toggle`** - Switch between on and off states
- **`/sw_hud status`** - Display current HUD visibility state

- **`/sw_beacons on`** - Enable and place beacon nodes at all waypoint locations
- **`/sw_beacons off`** - Disable and remove all beacon nodes
- **`/sw_beacons toggle`** - Switch between on and off states
- **`/sw_beacons status`** - Display current beacon state

These settings are persisted across server restarts and affect all connected players.

NOTE 1:

The GUI allows you to select a beacon color from 8 available options. When creating waypoints using the chat commands, a random color will be selected for the beacon.

**UPDATE:** Beacons are disabled by default but you can enable them using `/sw_beacons on` or in the Minetest config.

NOTE 2: "teleport" privilege is required.

Works with Minetest 5.2.0+

#### Installation

Extract zip to the mods folder.
