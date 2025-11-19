[![CI][status]][ci]
[![][spiv]][spi]
[![][spip]][spi]
[![License: MIT][mit]][license]

# Overview

Swift package containing useful C++ v23 headers for AUv3 app extensions and digital signal-processing (DSP) in general.
These were written specifically for use in an audio unit render thread, so there are no memory allocations done once a
render thread is started. Although it is is all C++, it does have instrumentation to support Swift C++ interoperability.
The [demo application][da] in the [auv-support][auv3-support] package illustrates how to use the headers to create an
AUv3 DSP [kernel][kernel] (the kernel just attenuates the input signal -- basically a volume control knob).

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

This collection was originally part of my [AUv3Support][AUv3Support] package, but with that repo being deprecated in
favor of the more modern [auv-support][auv3-support] package, it is now on its own.

# Usage

Add `.package(url: "https://github.com/bradhowes/DSPHeaders", from: "1.1.0")` to your Swift package dependencies, or
add the URL and version via Xcode `Package Dependencies` tab in the PROJECT editor of your Xcode project.

# Credits

All of the code has been written by myself over the course of several years working on AUv3 app extensions. There are a
collection of routines in [ConstMath][cm] that provide compile-time values for sine, natural log, and exponential
function. These are used to generate some lookup tables at compile time. The functions that do this were taken from
Lakshay Garg's [compile_time][ct] (no specific license) repo and Keith O'Hara's [GCEM][gcem] (Apache license) repo. I
started off with [compile_time][ct] but I lifted the natural log function from [GCEM][gcem]. Note that the use of these
compile-time methods are *only* for a very limited set of use-cases, all of which are not that demanding in terms of
precision.

[AUv3Support]: https://github.com/bradhowes/AUv3Support
[auv3-support]: https://github.com/bradhowes/auv3-support
[ep]: Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp
[crtp]: https://en.wikipedia.org/wiki/Curiously_recurring_template_pattern
[cm]: Sources/DSPHeaders/include/DSPHeaders/ConstMath.hpp
[ct]: https://github.com/lakshayg/compile_time
[gcem]: https://github.com/kthohr/gcem
[rf]: https://github.com/bradhowes/DSPHeaders/blob/788dc7833f2c9c5fb74b16e2d543c0df560b8cda/Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp#L376
[rr]: https://github.com/bradhowes/DSPHeaders/blob/788dc7833f2c9c5fb74b16e2d543c0df560b8cda/Sources/DSPHeaders/include/DSPHeaders/EventProcessor.hpp#L312
[da]: https://github.com/bradhowes/auv3-support/tree/main/AUv3Demo
[kernel]: https://github.com/bradhowes/auv3-support/blob/main/AUv3Demo/AUv3DemoExtension/Kernel/AUv3Demo_Kernel.hpp

[ci]: https://github.com/bradhowes/DSPHeaders/actions/workflows/CI.yml
[status]: https://github.com/bradhowes/DSPHeaders/actions/workflows/CI.yml/badge.svg
[spi]: https://swiftpackageindex.com/bradhowes/DSPHeaders
[spiv]: https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbradhowes%2FDSPHeaders%2Fbadge%3Ftype%3Dswift-versions
[spip]: https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbradhowes%2FDSPHeaders%2Fbadge%3Ftype%3Dplatforms
[mit]: https://img.shields.io/badge/License-MIT-A31F34.svg
[license]: https://opensource.org/licenses/MIT
