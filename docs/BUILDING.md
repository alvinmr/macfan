# Building MacFan

Requires Xcode 26 / Swift 6.2 or later.

```sh
make app     # builds and signs build/MacFan.app (ad-hoc)
make dmg     # universal app + DMG + checksum, exactly as releases are built
make run     # builds, then opens it
make test    # unit tests
```

Or from source without bundling: `swift run MacFan` (alerts and helper installation
need the bundled app).

## Command line

`macfanctl` reads the same data as the app. Handy for scripts and for bug reports.

```sh
swift run macfanctl sensors        # recognised sensors
swift run macfanctl sensors --all  # including unidentified ones
swift run macfanctl fans
swift run macfanctl battery
swift run macfanctl power          # system power draw and battery charge rate
swift run macfanctl apps           # apps using the most CPU
swift run macfanctl keys           # raw SMC temperature keys, for contributors
```

## The privileged helper

Reading temperatures needs no permission. *Changing* fan speed requires root, so
MacFan installs a small privileged helper the first time you pick a mode other than
Automatic (**Fans → Install Helper**). macOS will ask you to allow it in
**System Settings → General → Login Items → Allow in the Background**.

The helper's entire interface is three calls: *version*, *set fan target*, *give fans
back to macOS*. It:

- only accepts connections from an app signed as `io.github.alvinmr.MacFan` (and, for
  Developer ID builds, signed by the same team as the helper);
- returns all fans to macOS when the app disconnects, when it receives no command for
  20 seconds, and when it is stopped.

Remove it any time from **Settings → Helper → Uninstall Helper**.

### "The helper is registered but isn't responding"

Some macOS versions refuse to launch daemons from ad-hoc signed apps. Either sign with
a Developer ID:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make app
```

…or, for local development only, install the helper the classic way:

```sh
sudo scripts/install-helper-dev.sh install
sudo scripts/install-helper-dev.sh uninstall   # to remove
```

See also [ARCHITECTURE.md](ARCHITECTURE.md), [ADDING_SENSORS.md](ADDING_SENSORS.md) and
[RELEASING.md](RELEASING.md).
