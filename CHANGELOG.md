# Changelog

## [0.3.0](https://github.com/mattyo161/tiss/compare/v0.2.0...v0.3.0) (2026-07-15)


### Features

* add params caching script ([a8ff1bb](https://github.com/mattyo161/tiss/commit/a8ff1bb77bf0d2add2363f0f60a9d1a1f16aa5c3))
* integrate ajl — boto3-as-jsonl wrapper with cached reads ([0bfa0a6](https://github.com/mattyo161/tiss/commit/0bfa0a64190f2f9cbf39a7a6b57a0546b5e137b4))
* muscle-memory shortcuts via argv[0]-routed symlink shims ([d67304b](https://github.com/mattyo161/tiss/commit/d67304bb0082060dbdf8f756937f5aafbb617edc))
* seed a suggested shortcuts set (etc/shortcuts.example) ([e218186](https://github.com/mattyo161/tiss/commit/e218186d44c8183bf1c7612f72d977839ab89784))
* **ssm:** params — cached describe-parameters unwrapped to jsonl ([438fece](https://github.com/mattyo161/tiss/commit/438fece569aed1097189f269deba36921109e003))
* **tf:** port the production tf toolkit — icons, reports, safe apply ([b832df7](https://github.com/mattyo161/tiss/commit/b832df7ce26ff801848895ce2619ac76eeb84df9))
* **tf:** sweeps (--all/-j/--skip-fresh) and the deep-diff drift report ([82db80c](https://github.com/mattyo161/tiss/commit/82db80c41b675bb834cbf975b0c9e24a495c3f03))


### Bug Fixes

* 'tiss time' ran saveData — wrap the time helpers it was meant for ([46791b1](https://github.com/mattyo161/tiss/commit/46791b19ff322d8d3afda2ffc11612608557bdad))
* add AWS_DEFAULT_PROFILE as cachable ENV var ([7bf6824](https://github.com/mattyo161/tiss/commit/7bf682474054c320f9803d78fa1b8580bbeda233))
* SC2015 in shortcut parsing (shellcheck 0.9.0) ([7d3886a](https://github.com/mattyo161/tiss/commit/7d3886a1757385163a0d57035f2ad517d4746a06))
* shortcut collision check matched tiss's own sourced helpers ([ac542c5](https://github.com/mattyo161/tiss/commit/ac542c5adb861d6f76ee93d50412f4b5ad745a15))

## [0.2.0](https://github.com/mattyo161/tiss/compare/v0.1.1...v0.2.0) (2026-07-14)


### Features

* automated releases via conventional commits + release-please ([37ba922](https://github.com/mattyo161/tiss/commit/37ba922a24348cbfd1cbed79111fd67876467fe6))


### Bug Fixes

* probe /dev/tty by opening it; check AUTO_INSTALL=never first ([75ffad2](https://github.com/mattyo161/tiss/commit/75ffad25dfbaca6306c7a378fe62db51b528d315))
