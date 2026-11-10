# Changelog

## [0.4.0](https://github.com/alvinmr/macfan/compare/v0.3.2...v0.4.0) (2026-11-10)


### Features

* add GitHub links and a one-time star prompt ([c93e05a](https://github.com/alvinmr/macfan/commit/c93e05aebe431c1921f937b632b198bc21eedb17))
* add GitHub links, a one-time star prompt, and a rewritten README ([d5b974f](https://github.com/alvinmr/macfan/commit/d5b974f65fac67ec5287bbbc1055a6bd13e52661))


### Bug Fixes

* ask for a restart when an update leaves the helper unable to start ([e4ab9ce](https://github.com/alvinmr/macfan/commit/e4ab9ce7768e0ad9e1fcbf3a16d45d81360e7ebe))
* reset the helper without a restart after an update ([abfed26](https://github.com/alvinmr/macfan/commit/abfed26a1f94711d6c7623a8e18d8ca480ebbe23))
* reset the helper without a restart after an update ([b661f24](https://github.com/alvinmr/macfan/commit/b661f2462d7d05bc7bc1890438c2a24ad59633d1))

## [0.3.2](https://github.com/alvinmr/macfan/compare/v0.3.1...v0.3.2) (2026-11-09)


### Bug Fixes

* support lowercase SMC fan mode keys on M5 Macs ([#11](https://github.com/alvinmr/macfan/issues/11)) ([fd9a108](https://github.com/alvinmr/macfan/commit/fd9a10804fc62c6720b284591a12ed32cb915296))

## [0.3.1](https://github.com/alvinmr/macfan/compare/v0.3.0...v0.3.1) (2026-10-11)


### Bug Fixes

* keep learning Cooling Health while Smart Curve drives the fans ([ef43507](https://github.com/alvinmr/macfan/commit/ef4350728b7e8c2ea12df5f16303054c687a5f24))
* keep learning Cooling Health while Smart Curve drives the fans ([9a47514](https://github.com/alvinmr/macfan/commit/9a475146555c17139359212e10fc96f42c9061c4))

## [0.3.0](https://github.com/alvinmr/macfan/compare/v0.2.0...v0.3.0) (2026-10-04)


### Features

* add Insights with hot moments and cooling health learning ([31bc722](https://github.com/alvinmr/macfan/commit/31bc722470279e01f6e45203961533de4112514e))
* add Insights with hot moments and cooling health learning ([28c80df](https://github.com/alvinmr/macfan/commit/28c80df08bdf5171eb972e99959aa78dcc21efd3))


### Bug Fixes

* show CPU use as a share of the whole Mac, with recognisable names ([4716326](https://github.com/alvinmr/macfan/commit/4716326c68396e8dcda10897b8469f658bd413ba))
* stop hidden UI from redrawing, and show CPU as a share of the whole Mac ([2a9372f](https://github.com/alvinmr/macfan/commit/2a9372f0b18a74fe40f4946c9f7320f9904c4a22))
* stop redrawing windows and the menu bar panel nobody can see ([8bfd6da](https://github.com/alvinmr/macfan/commit/8bfd6da67053f9d0be6a4fbc16e3cb5379fd9eaa))

## [0.2.0](https://github.com/alvinmr/macfan/compare/v0.1.2...v0.2.0) (2026-10-04)


### Features

* show what's warming the Mac, history, power draw and pinned sensors ([3d9f5f3](https://github.com/alvinmr/macfan/commit/3d9f5f3978a31dce15a3f163902f5e5d3ca09aec))
* show what's warming the Mac, history, power draw and pinned sensors ([6bf346a](https://github.com/alvinmr/macfan/commit/6bf346a06e5d0fc0ba8b98a9e3c04408c93efb68))


### Bug Fixes

* stop MacFan from heating the Mac it watches ([a67f64f](https://github.com/alvinmr/macfan/commit/a67f64f4dbdf07cf1bd20f7be731bd41b0ba1184))

## [0.1.2](https://github.com/alvinmr/macfan/compare/v0.1.1...v0.1.2) (2026-10-04)


### Bug Fixes

* hand the fans back when temperature data goes missing ([c376ca3](https://github.com/alvinmr/macfan/commit/c376ca3a084ed9d55db5077a66f9103aa4846617))
* keep the duty to restore fans through failures, sleep and a stuck helper ([cfcfae2](https://github.com/alvinmr/macfan/commit/cfcfae29c5901a247af628b632d54c38f57ee136))
* only report fans as returned to macOS once they really are ([2ca3393](https://github.com/alvinmr/macfan/commit/2ca3393c41c6bc19279c082201d26ada72e52e21))

## [0.1.1](https://github.com/alvinmr/macfan/compare/v0.1.0...v0.1.1) (2026-10-04)


### Bug Fixes

* rename the CLI to macfanctl so it no longer overwrites the app binary ([66022a3](https://github.com/alvinmr/macfan/commit/66022a340ee35c2957d667806317fa9e8a8850ee))
