# SF2Lib: notes for coding agents

DSPHeaders is a C++ library for audio processing.

## Build and test

- In Xcode, use the `DSPHeaders` scheme.
- From the command line, `make test-macOS` (or `make` for both platforms plus coverage).

## Conventions

- Match the existing style: 2-space indent, 120-column lines, `/** ... */` doc comments with `@param` / `@returns`
- Don't commit build products or editor backup files (`.~/`, `*~`).
