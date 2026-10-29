# Roblox FPS Weapon System

**Developed by Dogi**

A focused Roblox Luau weapon-system portfolio project.

This repository contains the client, server, and weapon configuration code for a first-person rifle prototype. It is intentionally limited to the authored weapon logic; third-party models, Toolbox assets, maps, and unrelated game systems are not included.

## Features

- Server-authoritative hitscan validation
- Fire-rate, ammo, reload, and aiming state handling
- Damage zones with distance falloff
- Friendly-fire filtering
- Server-side spread and recoil pattern support
- Bounded lag-compensation snapshots for player hitboxes
- First-person viewmodel presentation
- Camera recoil, ADS, sway, walking bob, and local tracers

## Project structure

```
src/
  client/WeaponClient.client.lua
  server/WeaponService.server.lua
  shared/RifleConfig.lua
INSTALLATION.md
LICENSE
```

## Notes

The viewmodel is not included because it depends on game-specific rigging and assets. The client expects a `Workspace.ViewModelEditor.RifleViewModel` model with a `CameraBone` or `CameraPart`; ADS additionally uses an `AimAttachment`. The equipped Tool is expected to be named `Rifle`.

See [INSTALLATION.md](INSTALLATION.md) for the required Roblox Studio hierarchy.

## License

This code is public for portfolio viewing and review only. See [LICENSE](LICENSE).