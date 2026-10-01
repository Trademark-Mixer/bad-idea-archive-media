# 💎 Crystal Rush Simulator

A Roblox mining simulator. You mine glowing crystals, fill your backpack with gems,
sell them for coins, and spend the coins in the shop.

## What's in the game

- **5 zones**, each with its own look and sky color:
  🌻 Sunny Meadow → 💜 Crystal Caves → 🌋 Lava Volcano → ❄️ Frozen Peaks → 🌌 Galaxy Isles
- **Shop** with 11 pickaxes, 10 backpacks and 8 pets. Your best 3 pets follow you around and boost your gems.
- **🥚 Egg machines** (one at the spawn, one in each zone) hatch **21 rare pets**: Legendary pets
  glow and have an aura, and the Galaxy Egg has a 0.1% **Secret** pet. Every machine shows its chances.
- **🐾 Pets** window shows your whole collection. Pets you haven't found yet are black shadows.
- **Rebirths**: start over and earn more coins forever. You keep your pets.
- **Gates** between zones: walk up and press **E** to unlock the next zone.
- **Giant crystals**, a health bar on every crystal, sparkles, flying gems, sounds, and a glowing line that leads you to a sell pad when your backpack is full.
- **Progress saves automatically** once the game is published.
- Works on computer, phone and tablet.

## Way 1: open the ready-made file (easiest)

1. Download **`CrystalRush.rbxlx`** from this folder.
2. Open **Roblox Studio** → **File** → **Open from File…** → pick `CrystalRush.rbxlx`.
3. Press the big **▶ Play** button.

The world is built by the script when the game starts. In edit mode it looks
empty, but when you press **Play** everything appears.

## Way 2: copy and paste the 3 scripts

Use this if the file doesn't open for some reason.

1. In Studio, create a new **Baseplate** place.
2. **View** tab → turn on **Explorer** and **Properties**.
3. Make these 3 scripts (hover over the place in the Explorer → click **+**):

   | Where (in Explorer) | Add this | Rename it to | Paste the code from |
   |---|---|---|---|
   | **ReplicatedStorage** | ModuleScript | `GameShared` | [`src/shared/GameShared.luau`](src/shared/GameShared.luau) |
   | **ServerScriptService** | Script | `Main` | [`src/server/Main.server.luau`](src/server/Main.server.luau) |
   | **StarterPlayer → StarterPlayerScripts** | LocalScript | `Client` | [`src/client/Client.client.luau`](src/client/Client.client.luau) |

   The names must be exactly the same, with capital letters.
4. For the best graphics: click **Lighting** in the Explorer, then in Properties set **Technology** to **Future**.
5. Click **Workspace** and turn **StreamingEnabled** off.
6. Press **▶ Play**.

## How to play

- **Click** (or **tap**) a crystal to mine it. **Hold** the button to keep mining.
- When the backpack is full, walk onto a gold **💰 SELL** pad.
- Open the **🛒 Shop** to buy better pickaxes, bigger backpacks and pets.
- At an **egg machine**, press **E** to hatch 1 egg or **R** to hatch 3.
- Walk to a gate and press **E** to unlock the next zone.
- Use **🌀 Teleport** to jump between zones you've unlocked.
- At **75K coins** you can **♻️ Rebirth** for a permanent coin boost.

## Getting a new version into Studio

**If you haven't changed anything yourself:** download the new `CrystalRush.rbxlx` and open it
the same way as before (**File → Open from File…**). It already has everything.

**If you already published the game:** open the new file, then go to
**File → Publish to Roblox As…** and pick your existing game. That replaces the old version,
and players keep their saved progress.

**If you changed things in Studio yourself** (like prices), copy the new code into your 3 scripts:
double-click a script to open it, press **Ctrl+A** (select all), paste the new code over it, and do
the same for the other two. Then copy your changes back into `GameShared`.

## Publish it so friends can play

1. **File** → **Publish to Roblox** → give it a name and a description.
2. **Home** tab → **Game Settings** → **Security** → turn on **Enable Studio Access to API Services**.
   Saving then also works when you test in Studio.
3. In **Game Settings** → **Permissions** (or on the Creator Dashboard), set the game to **Public**.

Before you publish, Studio shows an orange line in the **Output** window:
`[Crystal Rush] Saving is off …`. That's normal. It goes away after you publish
and turn on API access.

## Change the game

Everything you'd want to tweak is in **`GameShared`** (in ReplicatedStorage):

- `Shared.Settings`: walk speed, mining range, how many crystals, respawn time, rebirth price …
- `Shared.Zones`: zone names, unlock prices, crystal health and gems, colors and sky mood
- `Shared.Pickaxes`, `Shared.Backpacks`, `Shared.Pets`: names, prices, power and colors
- `Shared.Eggs`: egg prices and which pets come out (with their chances in %)

**Testing tip:** set `StudioStartCoins = 1000000` to start with a million coins in Studio,
so you can try every item. Set it back to `0` before you publish.

## Files

```
CrystalRush.rbxlx            ← ready-made place file (open this in Studio)
default.project.json         ← Rojo project, used to build the .rbxlx
src/shared/GameShared.luau   ← settings, items and 3D models (ModuleScript)
src/server/Main.server.luau  ← map building, mining, shop, saving (Script)
src/client/Client.client.luau← screen UI, clicking, pets, effects (LocalScript)
```

If you change the files in `src/`, rebuild the place file with
[Rojo](https://rojo.space): `rojo build default.project.json -o CrystalRush.rbxlx`
