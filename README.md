[![CI](https://github.com/bradhowes/DSPHeaders/actions/workflows/CI.yml/badge.svg)][ci]
[![COV](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/bradhowes/9216666566d5badd2c824d352418/raw/DSPHeaders-coverage.json)][ci]
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbradhowes%2FDSPHeaders%2Fbadge%3Ftype%3Dswift-versions)][spi]
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbradhowes%2FDSPHeaders%2Fbadge%3Ftype%3Dplatforms)][spi]
[![License: MIT](https://img.shields.io/badge/License-MIT-A31F34.svg)][license]

# Overview

Swift package containing useful C++ v17 headers for AUv3 app extensions and digital signal-processing (DSP) in general.
These were written specifically for use in an audio unit render thread, so there are no memory allocations done once a
render thread is started.

The [EventProcessor][ep] template in the DSPHeaders product serves as the basis for all AUv3 audio rendering _kernels_.
The [EventProcessor::renderFrames][rf] method is the sole place that invokes `doRendering`, and it properly handles
ramping of AUv3 parameter changes. Continuing up the call chain, the [EventProcessor::render][rr] method invokes
[renderFrames][rf] while properly interleaving calls to it with MIDI event and parameter change processing.

You only need to define your own `doRendering` method to perform the sample rendering. Pretty much everything else is
handled for you. You can define additional methods if you wish, but only the `doRendering` one is mandatory.

Instead of using C++ virtual functions to dispatch to functionality held in derived classes, [EventProcessor][ep] relies
on the derived class being given as the template parameter. This setup is known as the ["curiously recurring template
pattern" (CRTP)][crtp]. The template also uses modern C++ traits techniques to detect if methods are present in your
class, and the compiler only generates code to call them when they are available.

This collection was originally part of my [AUv3Support][auv3support] package, but with that repo being deprecated this
is now on its own. 

# Credits

All of the code has been written by myself over the course of several years working on AUv3 app extensions. There are a
collection of routines in [ConstMath][cm] that provide compile-time values for sine, natural log, and exponential
function. These are used to generate some lookup tables at compile time. The functions that do this were taken from
Lakshay Garg's [compile_time][ct] (no specific license) repo and Keith O'Hara's [GCEM][gcem] (Apache license) repo. I
started off with [compile_time][ct] but I lifted the natural log function from [GCEM][gcem]. Note that the use of these
compile-time methods are *only* for a very limited set of use-cases, all of which are not that demanding in terms of
precision.

[ci]: https://github.com/bradhowes/DSPHeaders/actions/workflows/CI.yml
[auv3support]: https://github.com/bradhowes/AUv3Support
[spi]: https://swiftpackageindex.com/bradhowes/DSPHeaders
[license]: https://opensource.org/licenses/MIT
[ep]: Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp
[crtp]: https://en.wikipedia.org/wiki/Curiously_recurring_template_pattern
[cm]: Sources/DSPHeaders/include/DSPHeaders/ConstMath.hpp
[ct]: https://github.com/lakshayg/compile_time
[gcem]: https://github.com/kthohr/gcem
[rf]: blob/788dc7833f2c9c5fb74b16e2d543c0df560b8cda/Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp#L376
[rr]: blob/788dc7833f2c9c5fb74b16e2d543c0df560b8cda/Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp#L312
