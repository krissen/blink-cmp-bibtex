# Changelog

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
