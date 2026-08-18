# Changelog

## [0.12.0](https://github.com/krissen/blink-cmp-bibtex/compare/v0.11.0...v0.12.0) (2026-08-18)


### Features

* **discovery:** collect hook name and position alongside discovered names ([ff60e68](https://github.com/krissen/blink-cmp-bibtex/commit/ff60e68770daa512820eedb75704cef6d8479144))
* **discovery:** expose the project root to hooks ([093d37d](https://github.com/krissen/blink-cmp-bibtex/commit/093d37dd0e34a83f7b1b52497d8628535756d17a))
* **discovery:** find GAP package bibliographies outside the buffer ([3103ca6](https://github.com/krissen/blink-cmp-bibtex/commit/3103ca6906febc77b777f72f1166ff5226d2ffdd))
* **discovery:** name the manual a GAP package bibliography was declared in ([6165d31](https://github.com/krissen/blink-cmp-bibtex/commit/6165d3147e910cd451279372d256598596512c5c)), closes [#30](https://github.com/krissen/blink-cmp-bibtex/issues/30)
* **health:** list the bibliographies resolved for the current buffer ([9751d5d](https://github.com/krissen/blink-cmp-bibtex/commit/9751d5d66df3c6d666e894ff078a8d100e8c9804)), closes [#30](https://github.com/krissen/blink-cmp-bibtex/issues/30)
* **scan:** expose bibliography sources with their origins ([14e417d](https://github.com/krissen/blink-cmp-bibtex/commit/14e417d537cb57e428c996bba589940b8bf7f601))


### Bug Fixes

* **discovery:** defer to gapdoc only when the buffer declares a database ([97ac50c](https://github.com/krissen/blink-cmp-bibtex/commit/97ac50c49d7cccd06f5f5ed71f1a4f1f495f6a4d))
* **discovery:** describe a malformed record by how it was returned ([67b2545](https://github.com/krissen/blink-cmp-bibtex/commit/67b25456691779490913522df7d58db4bc3400cd))
* **discovery:** keep the shipped hooks returning file names ([7b2fcb0](https://github.com/krissen/blink-cmp-bibtex/commit/7b2fcb09aa1c74c22f481b8d316cf5913ad5b619))
* **discovery:** rank the manual candidates before capping them ([0a9880a](https://github.com/krissen/blink-cmp-bibtex/commit/0a9880a20974da19286290f90c2ca23b624eb012))
* **discovery:** validate the position a hook record carries ([5312a95](https://github.com/krissen/blink-cmp-bibtex/commit/5312a953d86ec3ec8a72fc95ca576a8ee694cfe8))
* **health:** look a resolved bibliography up in the global set ([a0b30a7](https://github.com/krissen/blink-cmp-bibtex/commit/a0b30a7321d61998e6bc4e0fdd40d69e2a8bc731))
* **health:** name the option a missing bibliography was configured in ([41d8685](https://github.com/krissen/blink-cmp-bibtex/commit/41d8685cac3f8afe2cb9c75ca0930450265135ea))
* **health:** report on the buffer the health check was run from ([0e7ff7a](https://github.com/krissen/blink-cmp-bibtex/commit/0e7ff7a154be127eed80def458dd81ba227f38b3))
* **health:** resolve the path options once per report ([f5e4ecb](https://github.com/krissen/blink-cmp-bibtex/commit/f5e4ecb173193ac5aaf2549d35bc5f9cbc3ac5f8))
* **health:** word a missing bibliography by where it came from ([0b6078d](https://github.com/krissen/blink-cmp-bibtex/commit/0b6078db9b8addd13edf02e390899d665b4f35c1))
* **scan:** anchor relative global_files entries the way the scanner does ([8b1adf8](https://github.com/krissen/blink-cmp-bibtex/commit/8b1adf80ab090caa2cb2ee121ca15e29e0de5e83))
* **scan:** identify bibliographies by their real path ([0ada519](https://github.com/krissen/blink-cmp-bibtex/commit/0ada519ef8de8acb5e8def3abe492a20cca05383))
* **source:** share the global-file check with the scanner ([6264816](https://github.com/krissen/blink-cmp-bibtex/commit/6264816ec6fc78f330bec7417ac3a53ddd5110f0))


### Performance Improvements

* **discovery:** keep the package cache across buffers ([58767b1](https://github.com/krissen/blink-cmp-bibtex/commit/58767b126493352f13efe19c22ca62fbefe7370c))
* **discovery:** validate the package cache on a coarser trigger ([c1370c1](https://github.com/krissen/blink-cmp-bibtex/commit/c1370c18c42960963b079fc45cf0678b927aa2e4))

## [0.11.0](https://github.com/krissen/blink-cmp-bibtex/compare/v0.10.0...v0.11.0) (2026-08-14)


### Features

* **health:** report discovery chains ([15052ec](https://github.com/krissen/blink-cmp-bibtex/commit/15052ec12e45c239880751c61004c9890fce3d24)), closes [#27](https://github.com/krissen/blink-cmp-bibtex/issues/27)
* **scan:** register bib discovery hooks per filetype ([ae53a8d](https://github.com/krissen/blink-cmp-bibtex/commit/ae53a8d7aa735897408ccb49d1376142628a8c22)), closes [#27](https://github.com/krissen/blink-cmp-bibtex/issues/27)
* **scan:** turn buffer discovery off with discovery = false ([93289ec](https://github.com/krissen/blink-cmp-bibtex/commit/93289ec42fc81eb57060c9b03b0ccab9913e00d5)), closes [#27](https://github.com/krissen/blink-cmp-bibtex/issues/27)


### Bug Fixes

* **config:** tolerate non-table option values ([751792b](https://github.com/krissen/blink-cmp-bibtex/commit/751792ba546fab92fc0fd16edbc74d8845ebc9db)), closes [#27](https://github.com/krissen/blink-cmp-bibtex/issues/27)
* **init:** bound the entry lookup to two completion rounds ([803f6a2](https://github.com/krissen/blink-cmp-bibtex/commit/803f6a24ab1f2a704866b1b9e512602eb612cf78)), closes [#25](https://github.com/krissen/blink-cmp-bibtex/issues/25)
* **init:** detect citation keys through the matcher chain ([62f75a6](https://github.com/krissen/blink-cmp-bibtex/commit/62f75a67d143c74368f745a46cdd7c163744c0c1)), closes [#26](https://github.com/krissen/blink-cmp-bibtex/issues/26)

## [0.10.0](https://github.com/krissen/blink-cmp-bibtex/compare/v0.9.0...v0.10.0) (2026-08-14)


### Features

* **scan:** discover GAPDoc bibliography declarations ([#20](https://github.com/krissen/blink-cmp-bibtex/issues/20)) ([ad7e10c](https://github.com/krissen/blink-cmp-bibtex/commit/ad7e10cc4cca64306ed2d174ecf7aaca2e60514a))

## [0.9.0](https://github.com/krissen/blink-cmp-bibtex/compare/v0.8.0...v0.9.0) (2026-08-14)


### Features

* add checkhealth for matcher configuration ([6a6010b](https://github.com/krissen/blink-cmp-bibtex/commit/6a6010b8233f8250afda2bca6418b3102a0b7c96))
* honour per-matcher prefix sanitization ([1d41854](https://github.com/krissen/blink-cmp-bibtex/commit/1d418549a925ec82187cea92be46b6c6142392ba))
* implement enabled and get_trigger_characters ([42fc121](https://github.com/krissen/blink-cmp-bibtex/commit/42fc1211f819fe85ac26fad717b7d20aa4e20424))
* **matchers:** add GAPDoc citation matcher ([#20](https://github.com/krissen/blink-cmp-bibtex/issues/20)) ([fbf4d98](https://github.com/krissen/blink-cmp-bibtex/commit/fbf4d982fc48905f7d86d7174189950003ffbd4f))
* user-extensible citation matchers, test suite, CI and releases ([#20](https://github.com/krissen/blink-cmp-bibtex/issues/20)) ([137e30b](https://github.com/krissen/blink-cmp-bibtex/commit/137e30b180383af56fc1fda6e20af72172d1dc9f))


### Bug Fixes

* **config:** make list options replace defaults instead of index-merging ([9962568](https://github.com/krissen/blink-cmp-bibtex/commit/99625681d3afcaac55a5740456661692713e79ba))
* **health:** normalize file options before counting ([7f9c916](https://github.com/krissen/blink-cmp-bibtex/commit/7f9c916646cdbef27d62a9ccf3894ddae4cdb7a3))
* **health:** report shipped dormant matchers as info rather than a warning ([53c60f0](https://github.com/krissen/blink-cmp-bibtex/commit/53c60f03ed81fcf01533d08f48ffe06adc0e1a28))
* **matchers:** inherit shipped spec fields for shorthand matcher forms ([98241bc](https://github.com/krissen/blink-cmp-bibtex/commit/98241bc00290261a99a42da5b849f707bdd33899))
* **matchers:** reject malformed optional spec fields ([4627911](https://github.com/krissen/blink-cmp-bibtex/commit/4627911f4be5903fbcec175afae913b2dae3cb10))
* **matchers:** restrict typst fallback to typst buffers ([15c1ba6](https://github.com/krissen/blink-cmp-bibtex/commit/15c1ba631ee19a0ab181c69ac2a3bb04b005641c))
* **matchers:** scope failure tracking to matcher and filetype ([79d6c82](https://github.com/krissen/blink-cmp-bibtex/commit/79d6c82544ecf0180faf391fb000408a75202954))
* **matchers:** stringify matcher errors before reporting them ([b9dcb25](https://github.com/krissen/blink-cmp-bibtex/commit/b9dcb257558ab79fe529f9bf16e61427a5b1651d))
* **matchers:** validate matcher results in dispatch ([ec8b730](https://github.com/krissen/blink-cmp-bibtex/commit/ec8b730783e9ec232631108bed6de31ba28f1c06))
* **parser:** skip `@comment`, `@string` and `@preamble` blocks ([9b65c3d](https://github.com/krissen/blink-cmp-bibtex/commit/9b65c3dd9a03fcdfbf4e18c087b178dc7a217f5d))
* return a single value from normalize_whitespace ([34e1dad](https://github.com/krissen/blink-cmp-bibtex/commit/34e1dadfcccfccf6510a5747c24eca290c9e1673))
* surface bootstrap download failures ([a554878](https://github.com/krissen/blink-cmp-bibtex/commit/a554878f63a423310581681afb0bdc1d254c8c6f))
