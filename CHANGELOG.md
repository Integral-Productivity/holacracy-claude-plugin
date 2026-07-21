# Changelog

## [0.7.0](https://github.com/Integral-Productivity/holacracy-claude-plugin/compare/v0.6.0...v0.7.0) (2026-07-21)


### Features

* **coach:** add read-only holacracy-coach subagent + wire /holacracy:governance ([#99](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/99)) ([c37bcaf](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/c37bcaf8b8d2a9e204e1911ffc85c062eb92da9d))
* **governance:** adopt devops-excellence standard (.github/workflows/auto-merge.yml) ([#59](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/59)) ([1ba27aa](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/1ba27aaac764b341cff2cc4d8a5bf234fc22eb06))
* **governance:** adopt devops-excellence standard ([#53](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/53)) ([a780264](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/a780264c89204752bc388309d372ea5e8b80e477))
* **governance:** live-domain artifact-routing resolver (Track A P1, [#63](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/63)) ([#72](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/72)) ([44dd8f5](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/44dd8f5f72f54179e85c48ac51cc62f90bca6d24))
* **hooks:** SessionStart role-grounding directive (Track A PDCA-1, [#62](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/62)) ([#70](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/70)) ([f599bdb](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/f599bdb2bd3cacf8180f81c53dd95fafedb85b4a))
* **project-triage:** add /holacracy:capture-project capture-time guardrail (Phase 2, [#75](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/75)) ([#87](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/87)) ([bbd6855](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/bbd6855346923bc4341f21ae42e4555208b150d4))
* **project-triage:** add /holacracy:review-project adversarial project-review panel (Phase 1) ([#77](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/77)) ([794d093](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/794d0933dc9c40e3bf6601f1863081d20dab6367)), closes [#74](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/74)
* **project-triage:** add /holacracy:stalled-project-sweep back-of-loop sweep (Phase 3, [#76](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/76)) ([#88](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/88)) ([509b711](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/509b711bf1b71b86d72b52b3170a3028604f3ee4))


### Bug Fixes

* **ci:** pass declared OP_AUTOMERGE_PUBLIC_TOKEN to reusable auto-merge (unbreak startup_failure) ([#96](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/96)) ([97354e5](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/97354e56f52f6e932a42fae52c31a01d8fcd5fd9)), closes [#92](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/92)
* **ci:** repoint workflow callers to the public reusable-workflows host ([#58](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/58)) ([13d8631](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/13d8631b769cb154e2856fac72923077d02c5cb3))

## [0.6.0](https://github.com/Integral-Productivity/holacracy-claude-plugin/compare/v0.5.0...v0.6.0) (2026-06-18)


### Features

* Secretary pre-tactical-prep routine + agentic-routines mechanism ([#45](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/45)) ([a9874b9](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/a9874b9da8ea7471e2673044e0f31701f14e2244))

## [0.5.0](https://github.com/Integral-Productivity/holacracy-claude-plugin/compare/v0.4.0...v0.5.0) (2026-06-16)


### Features

* opt-in inherited-context load for /holacracy:context (--inherited) ([#37](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/37)) ([9b9aa97](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/9b9aa97deee977ae26b27d0340dbea8ce2a3c6a4))

## [0.4.0](https://github.com/Integral-Productivity/holacracy-claude-plugin/compare/v0.3.3...v0.4.0) (2026-06-08)


### Features

* add /holacracy:governance command ([#32](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/32)) ([fec406a](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/fec406a630d4f58bb7793e1b510f081f0f718bba)), closes [#7](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/7)

## [0.3.3](https://github.com/Integral-Productivity/holacracy-claude-plugin/compare/v0.3.2...v0.3.3) (2026-05-28)


### Bug Fixes

* **security:** mask PEM line-by-line in inlined workflow copies ([#28](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/28)) ([deddfac](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/deddface310b9edffa11eed65b85f7621fd19f20)), closes [#21](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/21)

## [0.3.2](https://github.com/Integral-Productivity/holacracy-claude-plugin/compare/v0.3.1...v0.3.2) (2026-05-28)


### Bug Fixes

* **docs:** name the no-force-push ruleset in promote-stable.yml comment ([#26](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/26)) ([c6bdca6](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/c6bdca65d29d6c1576d5e65af41f515450a0b40d)), closes [#21](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/21)

## [0.3.1](https://github.com/Integral-Productivity/holacracy-claude-plugin/compare/v0.3.0...v0.3.1) (2026-05-28)


### Bug Fixes

* **ci:** inline release-please workflow (cannot call private reusable from public repo) ([#23](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/23)) ([5a9ba18](https://github.com/Integral-Productivity/holacracy-claude-plugin/commit/5a9ba1836924b0be7bad43eb61f331009175d3cf))
