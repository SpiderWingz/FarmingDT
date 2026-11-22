# farmingDT

This is a VORP/oxmysql public-plot farming resource. It persists public fields and crops, enforces the three-plot owner cap, and follows the supplied black-and-gold/inventory UI direction.

## What is configurable

Edit `config.lua` to change the player plot cap, interaction distance, plot layouts, crop seeds, growth-stage durations, crop props, harvested items and amounts, water supplies, fertilizers, their effects, and all UI heading copy. The UI builds its supply cards from the payload it receives; it does not need a frontend edit when a dev adds another seed, water source, or fertilizer entry.

`Config.PlotLayouts` defines the supported land sizes. When the placement code creates a plot, it stores the chosen layout and builds that many slots. Send `{ rows = n, columns = n }` as `plot.layout` and `{ width = n, length = n, unit = 'FT' }` as `plot.dimensions` with the plot payload. The UI renders every slot returned and uses the saved column count for the field grid, so small and large plots do not have the same fixed number of furrows. The screen uses a compact inventory-style grid to keep larger layouts scannable.

`Config.Consumables` is the source of truth for water and fertilizer. Adding a new configured entry automatically adds it to the NUI. `effect.moisture` controls watering strength; `effect.fertility` controls how much crop fertility it adds. `Config.Farming.fertilityGrowthBonus` and `fertilityYieldBonus` control how strongly fertility changes maturity time and harvest yield.

`Config.AllowedPlacementZones` can optionally restrict field placement to configured circles. `Config.PlotVisual.model` controls the tilled-land prop; `Config.CropVisuals.enabled` controls the configured `propByStage` crop props. Both visuals are off by default until your art team provides valid streamed models.

`Config.ActionAnimations` controls the scenario and duration used for planting, watering, fertilizing, treatment, and harvesting. The UI closes while the player performs the configured in-world action; pressing Backspace cancels it before the server action is submitted.

An action can call a native scenario, a direct RDR dictionary/clip, a local event, or an export from another animation resource. See [animation integration examples](docs/animation-integrations.md).

`Config.Seasons`, `Config.Weather`, `Config.Disease`, `Config.Access`, and `Config.Market` are independent advanced modules. Disease, seasons, weather, and market commands are off by default until their item/economy rules are configured.

`Config.Diseases` currently includes drought wilt, root rot, powdery mildew, field pests, and crop blight. Each disease controls its moisture trigger, chance, and growth penalty. Treatment items define exactly which disease keys they cure. Root rot, pests, and blight are hidden until a player with one of the job names in `Config.Diagnosis.jobs` diagnoses the crop; treatment is unavailable beforehand.

## Test the interface

1. Place the folder in your server's `resources` directory.
2. Ensure `oxmysql`, `vorp_core`, and `vorp_inventory` before this resource.
3. Add `ensure farmingDT` to `server.cfg`.
4. Add the configured `farm_plot_kit`, seed, water, fertilizer, and harvest items to your VORP items table.
5. Join the server. Use the `farm_plot_kit` in VORP inventory. For placement testing, set `Config.Debug = true`, then use `/farmplace [small|medium|large]`.

The database schema is created automatically at startup. A copy is also provided in `sql/public_farming.sql` for server operators who prefer migrations. `/farmui` remains a local UI-only preview command.

## Current gameplay loop

1. Use a `farm_plot_kit` (or `/farmplace` in development) and confirm its position with the interaction key.
2. The server validates the three-plot cap, placement distance, spacing, and the placement item before creating the persistent public plot.
3. Any nearby player opens the plot and chooses a furrow. They can plant seeds, apply configured water/fertilizer, and harvest a mature crop.
4. The server validates distance, inventory count, and the current crop state for every action before updating MySQL and VORP inventory.

To show a physical tilled-land object, configure `Config.PlotVisual.model` with an available streamed RedM prop supplied by your art team. Until then, the interaction label remains visible at the plot coordinate.

## Integration contract

To open a menu from another server resource, call this client event:

```lua
TriggerClientEvent('public_farming:client:openPlot', source, payload)
```

The payload has this shape:

```lua
{
  plot = {
    id = 'plot-42',
    label = 'Public Field · Plot 42',
    layout = { rows = 3, columns = 4 },
    dimensions = { width = 12, length = 18, unit = 'FT' },
    slots = {
      {
        id = 'slot-01', number = '01', state = 'growing', label = 'Young Corn',
        crop = 'Corn', growth = 48, moisture = 38, fertility = 45
      }
    }
  },
  supplies = {
    {
      id = 'water_bucket', category = 'water', label = 'Water Bucket',
      description = 'Raises soil moisture by 35 points.', count = 3, icon = 'W'
    }
  },
  ui = Config.UI
}
```

The selected-furrow panel shows the crop, real elapsed crop age, growth percentage, life stage, moisture, fertility, health, and disease status. Diseases configured as `requiresDiagnosis` deliberately display as unknown until a configured farmer completes diagnosis.

The UI sends `farmAction` back with `action`, `plotId`, `slotId`, and `supplyId`. Treat it as a request only. The server validates proximity, item ownership, crop state, and configuration; locks the slot while applying the database and inventory update; then refreshes the plot for nearby users.

## Deliberate public-plot behavior

The UI does not show an ownership gate: every player can tend a publicly placed plot and harvest a mature crop. The server tracks plot ownership only for the three-plot limit and owner/admin plot removal.

## Commands

- `/farmui` — local UI preview only.
- `/farmplace [small|medium|large]` — placement mode when `Config.Debug = true`; normal players still need a plot kit if Debug is off.
- `/farmremove` — remove the nearest owned plot; admins may remove any nearby plot.
- `/farmadmin season <spring|summer|autumn|winter>` — admin-only runtime season change.
- `/farmadmin weather <clear|rain|drought|storm>` — admin-only runtime weather change.
- `/farmadmin mature <plotId> <slotIndex>`, `/farmadmin cure <plotId> <slotIndex>`, `/farmadmin delete <plotId>` — admin maintenance tools.
- `/farmbuy <item> <amount>` and `/farmsell <item> <amount>` — optional market commands when `Config.Market.enabled = true`.

Other server resources may update modifiers with `exports.farmingDT:setSeason('spring')` and `exports.farmingDT:setWeather('rain')`.
