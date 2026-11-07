# Retired Mac menu-bar companion

The separate `Hash Fleet Menu Bar.app` and its `app.hashfleet.menubar` LaunchAgent are retired. Do not install them alongside the current Mac product.

Use the **HashFleetMac** native macOS target instead. One `Hash Fleet.app` executable owns the workspace, menu-bar status item, monitoring lifecycle and shared in-memory fleet state. Closing the workspace keeps that application running. Quit stops both surfaces, with no helper or crash-restarting LaunchAgent.

See [native Mac installation](MAC-NATIVE-INSTALL.md) for packaging, signature checks, reversible installation and local-versus-public release limitations. The iOS/iPad product must not be installed directly on macOS. Use the iOS simulator for that build on a Mac.

## Inspect or remove a legacy job

`Scripts/hash-fleet-menu-bar.sh install` intentionally fails before changing the system. The remaining legacy commands are for inspection and explicitly authorized cleanup only:

```sh
Scripts/hash-fleet-menu-bar.sh status
Scripts/hash-fleet-menu-bar.sh render
Scripts/hash-fleet-menu-bar.sh uninstall
```

Back up the old bundle, relevant data and LaunchAgent plist before cleanup. The uninstall command affects only the matching per-user LaunchAgent; it does not delete the app or user data. Never launch the retired companion as a workaround for a problem in the native application.

The old `MacMenuBar/` source and prior Git history remain available for historical reference, not as the production installation path. Earlier acceptance records describing cached App Group snapshots and a separate helper are dated historical evidence, not the current architecture.
