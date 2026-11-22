# Animation integrations

Each entry in `Config.ActionAnimations` can use one of three providers:

- `native` — use the configured RDR scenario directly.
- `anim` — play a dictionary/clip pair directly from RDR's animation assets.
- `event` — trigger a local client event exposed by another animation resource.
- `export` — call a client export supplied by another started resource.

`farmingDT` waits for the entry's configured `duration` before submitting the normal server-validated farm action. The server never trusts an animation provider to grant items or update crops.

## Native scenario

```lua
seed = {
    provider = 'native',
    scenario = 'WORLD_HUMAN_FARMER_WEEDING',
    duration = 5500,
    label = 'Planting seeds',
    clearTasks = true,
    fallbackToNative = true
}
```

## femga/rdr3_discoveries dictionary and clip

The supplied `ingameanims_list.lua` link is a reference catalog, not an installable animation resource. Copy the exact dictionary and clip pair you want from the list into an `anim` provider entry. `farmingDT` requests the dictionary and calls the RDR animation native itself.

```lua
water = {
    provider = 'anim',
    dictionary = 'replace_with_dictionary_from_the_list',
    clip = 'replace_with_clip_from_the_list',
    flags = 1,
    blendIn = 1.0,
    blendOut = 1.0,
    playbackRate = 1.0,
    duration = 4500,
    label = 'Watering crop',
    clearTasks = true,
    fallbackToNative = true,
    scenario = 'WORLD_HUMAN_BUCKET'
}
```

Use this only with a dictionary/clip confirmed to work for the player ped on your RedM build. If it cannot load, `fallbackToNative = true` uses the configured scenario instead.

## External client event

Use this when a resource documents a client event to play an emote or animation.

```lua
water = {
    provider = 'event',
    resource = 'my_animations', -- optional guard; it must be started when set
    event = 'my_animations:client:playEmote',
    arguments = { 'watering_can' },
    stopEvent = 'my_animations:client:stopEmote',
    duration = 4500,
    label = 'Watering crop',
    clearTasks = false,
    fallbackToNative = true,
    scenario = 'WORLD_HUMAN_BUCKET'
}
```

The configured values in `arguments` are passed first. `farmingDT` appends this context table as the last argument:

```lua
{
    action = 'water', duration = 4500, label = 'Watering crop',
    plotId = 12, slotId = 44, request = { ... }
}
```

## External client export

Use this when the other resource exposes a client export. The resource must be started before the action begins.

```lua
fertilizer = {
    provider = 'export',
    resource = 'my_animations',
    export = 'playEmote',
    arguments = { 'spread_fertilizer' },
    stopExport = 'stopEmote',
    duration = 5000,
    label = 'Fertilizing crop',
    clearTasks = false,
    fallbackToNative = true,
    scenario = 'WORLD_HUMAN_FARMER_WEEDING'
}
```

If an event/export cannot be called and `fallbackToNative = true`, `farmingDT` uses the configured `scenario`. Set `provider = 'none'` if another resource handles the animation from the lifecycle hooks below and no start call should occur.

## Lifecycle hooks for custom resources

Any client resource can listen to these local events:

```lua
AddEventHandler('farmingDT:client:animationStarted', function(context)
    -- Play a fully custom animation using context.action.
end)

AddEventHandler('farmingDT:client:animationStopped', function(context, cancelled)
    -- Stop / clean up the custom animation.
end)
```

These hooks are client-local. They should control visuals only; crop, inventory, and reward changes stay in `farmingDT`'s server code.
