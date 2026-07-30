# Installation

Create the following hierarchy in Roblox Studio:

```
ReplicatedStorage
  WeaponSystem
    Configs
      RifleConfig
    Remotes
      FireWeapon
      ReloadWeapon
      SetAiming
      WeaponEffects
  WeaponTemplates
    Rifle

ServerScriptService
  WeaponSystem
    WeaponService

StarterPlayer
  StarterPlayerScripts
    WeaponClient

Workspace
  ViewModelEditor
    RifleViewModel
```

## Required weapon objects

The `Rifle` Tool needs a `Handle` and should contain:

- `AimAttachment`
- `MuzzleAttachment`
- `GripAttachment`

The first-person `RifleViewModel` needs:

- `CameraBone` or `CameraPart`
- `AimAttachment` for ADS alignment
- `MuzzleAttachment` for local tracer origin

## Configuration

Edit `RifleConfig.lua` to tune ammo, RPM, reload time, damage, falloff, spread, ADS, recoil, and lag-compensation limits.

The client sends aim direction and time data. The server verifies weapon state, direction, origin distance, fire rate, ammunition, reload state, spread, and target damage before accepting a shot.

## Integration

This is a rifle-focused portfolio slice, not a drop-in full game framework. New weapons should receive their own config and tool/viewmodel assets, then be routed through a shared weapon registry or a generalized service before production use.