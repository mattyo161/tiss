# Changelog

## [2.0.0](https://github.com/mattyo161/tiss/compare/v1.0.0...v2.0.0) (2026-07-18)


### ⚠ BREAKING CHANGES

* `tiss self <reserved-word>` no longer routes to anything; use the top-level word directly (`tiss doctor`, `tiss init`, `tiss config list`, etc.)

### Features

* fzf picker for did-you-mean with multiple candidates ([b2ec9b4](https://github.com/mattyo161/tiss/commit/b2ec9b428cdd006acac3efb86ed7a0edf6a9ecb9))
* kill legacy `tiss self X` spelling now that we're at 1.0 ([47467b2](https://github.com/mattyo161/tiss/commit/47467b2620d338018738b8f78311fd301278691f))
* tiss env --yaml/--toml + props2yaml/props2toml/yaml2props/toml2props ([ff17f7b](https://github.com/mattyo161/tiss/commit/ff17f7b07872852e8641a80b091b35c90aa470d9))

## [1.0.0](https://github.com/mattyo161/tiss/compare/v0.3.0...v1.0.0) (2026-07-17)


### ⚠ BREAKING CHANGES

* the tf wrapper commands (tf plan/apply/report) are no longer in core — install them with: tiss +devops
* 'tiss self tree' is now 'tiss pile'; 'tiss self cd' is removed; rc integration no longer emits a wrapper function.

### Features

* 'tiss install TOOL' — the explicit front door to lazy install ([a4c8878](https://github.com/mattyo161/tiss/commit/a4c88787cda956bd1f69153c88a7a9a9046e486d))
* bootstrap mise on empty boxes; guide brew activation ([3194a48](https://github.com/mattyo161/tiss/commit/3194a48e9cf13ad9943c8c540a8b564dd36227f0))
* **cache:** announce cache hits on stderr (TISS_CACHE_NOTICE) ([5b78f1d](https://github.com/mattyo161/tiss/commit/5b78f1dee9e1a5d94f5096c0573a1aff73f95c82))
* **data:** lsData — tty table, cache entries summarized not listed ([d2ca686](https://github.com/mattyo161/tiss/commit/d2ca686a0feb5afad0e2d72193fe349cfaedabda))
* did-you-mean — typos offer the closest tiss command ([82621ee](https://github.com/mattyo161/tiss/commit/82621ee61d423ba8b6f50500d639e9d1686e021d))
* **env:** bare 'tiss env' shows the resolved environment; props&lt;-&gt;json leaves ([98213c7](https://github.com/mattyo161/tiss/commit/98213c71d7698643c876e2bd58bd196586b91c26))
* if the xlsx file exists then append the sheet ([e881361](https://github.com/mattyo161/tiss/commit/e8813611ffb752b970cd345709eaec004ae8b3c8))
* offer to write the activation line into the shell rc ([f4a6704](https://github.com/mattyo161/tiss/commit/f4a67043490294e106d45477cc9ca5fe43dae3ed))
* **pile:** 'pile new' scaffolder; 'tiss test' runs enabled trees' tests ([f131552](https://github.com/mattyo161/tiss/commit/f1315524b1ee28c97c4f2b9192add1d66ce9572f))
* reserved lexicon + the pile — meta commands go top-level ([9345093](https://github.com/mattyo161/tiss/commit/934509391c5f42cecee15ebbaafc1200c5482111))
* tf moves out of core into the devops tree ([cc2e9c8](https://github.com/mattyo161/tiss/commit/cc2e9c84991b10e807bc440a12886e02597e79cd))
* tree packages — +name/-name syntax for git-distributed overlay trees ([1f6c673](https://github.com/mattyo161/tiss/commit/1f6c673087cbbc532c088d6688c38b7ec068fc6d))


### Bug Fixes

* **ci:** SC2153 false positive in test_env.sh (shellcheck 0.9.0) ([900d3dc](https://github.com/mattyo161/tiss/commit/900d3dcc587c494e025a349493b493684d109c79))
* **pile:** package branch convention is tiss/&lt;name&gt;, not tree/&lt;name&gt; ([2cc0979](https://github.com/mattyo161/tiss/commit/2cc097960d64954ab04228fbb448a75d7cb24da5))
* **tests:** harness isolates the full TISS_* environment ([baf538f](https://github.com/mattyo161/tiss/commit/baf538f5b0367fc7228ee3522f239635fa35d7a0))
* **tests:** install(1) usage text differs on GNU vs BSD ([09b3ab3](https://github.com/mattyo161/tiss/commit/09b3ab3ca4af2348775a996e616f1885338dd992))


### Reverts

* drop tiss ajl wrapper (scripts/ajl/_self.sh) ([a7936ce](https://github.com/mattyo161/tiss/commit/a7936ce3439f057221f81706934e8d53cb4898d1))

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
