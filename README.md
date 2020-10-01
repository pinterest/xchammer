# XCHammer
> If all you've got is Xcode, your only tool is a 🔨

[![Build Status](https://travis-ci.org/pinterest/xchammer.svg?branch=master)](https://travis-ci.org/pinterest/xchammer)

XCHammer generates Xcode projects from a [Bazel](https://bazel.build/) Workspace.

- [x] Complete Bazel Xcode IDE integration
    - [x] Bazel build and run via Xcode
    - [x] Xcode test runner integration
    - [x] Full LLDB support without DSYM generation
    - [x] Autocompletion and indexing support
    - [x] Renders Bazel's progress in Xcode's progress bar
    - [x] Optionally import index's via [index-import](https://github.com/lyft/index-import) with [Run Scripts](sample/UrlGet/BUILD.bazel#L39)
    - [x] Customize Bazel invocations for Xcode
- [x] Incremental project generation
- [x] [Focused](Docs/PinterestFocusedXcodeProjects.md#xcfocus-aka-focused-projects) Xcode projects
- [x] Xcode build Bazel targets _without Bazel_
- [x] Optionally Bazel build Xcode projects
   - [x] Define and compose Xcode projects [in Skylark](#bazel-build-xcode-projects)
   - [x] Builds reproducible and remote cacheable projects
- [x] Automatically updates Xcode projects

## Usage

_Note: this README is intended to be a minimal, quick start guide to XCHammer.
To learn more about XCHammer see [Introducing
XCHammer](Docs/FastAndReproducibleBuildsWithXCHammer.md) and [The XCHammer
FAQ](Docs/XCHammerFAQ.md). To learn more about Bazel, see [Bazel for iOS
developers](Docs/BazelForiOSDevelopers.md). To learn about how Pinterest uses
XCHammer see [Introducing
XCHammer](Docs/FastAndReproducibleBuildsWithXCHammer.md) and [Pinterest Focused
Xcode Projects](PinterestFocusedXcodeProjects.md)_

### Bazel build Xcode projects

First, pull XCHammer into the `WORKSPACE` file:

_Ideally, pull in a release optimized binary build to keep XCHammer's
dependencies, Swift version, Xcode version, compiler flags, Bazel version, and
build time outside of the main iOS/macOS application's WORKSPACE. To easily
achieve this, github CI creates a binary release artifact on receiving a new
tag._

```py
# WORKSPACE
# Recommended approach - the CI auto releases when you push a tag matching `v*`
# The release prefix is the _tested_ bazel version, and XCHammer is often
# forwards and backwards compatible
http_archive(
    name = "xchammer",
    urls = [ "https://github.com/pinterest/xchammer/releases/download/v3.4.1.0/xchammer.zip" ],
)

# Vendor a binary release of xchammer e.g. from a github action `artifact` on a PR
#  https://github.com/pinterest/xchammer/pull/262/checks?check_run_id=1195532626
# local_repository(
#    name = "xchammer",
#    path = "tools/xchammer"
# )

# Pull from source
# git_repository(
#    name = "xchammer",
#    remote = "https://github.com/pinterest/xchammer.git",
#    commit = "[COMMIT_SHA]"
# )
```
_note: for development, `make build` and the `xchammer_dev_repo` target allow a
WORKSPACE to consume XCHammer built out of tree but point to the latest build,
symlinked in `bazel-bin`:
`--override_repository=xchammer=/path/to/xchammer/bazel-bin/xchammer_dev_repo`.
It's also possible to use `local_repository` and override it using
`--override_repository=xchammer=/path/to/xchammer`_

Next, create an `xcode_project` target including targets:
```
# BUILD.Bazel
load("@xchammer//:xcodeproject.bzl", "xcode_project")
xcode_project(
    name = "MyProject",
    targets = [ "//ios-app:ios-app" ],
    paths = [ "**" ],
)
```

Finally, build the project with Bazel
```bash
bazel build MyProject
```

### CLI Usage ( Non Bazel built projects )

XCHammer also works as a standalone project generator. kirst build XCHammer and
install to the path:

```bash
# Installs to `/usr/local/bin/`
make install
```
Then, generate using a [XCHammerConfig](Sources/XCHammer/XCHammerConfig.swift).

```bash
xchammer generate <configPath>
```

## Configuration Format

XCHammer is configured via a `yaml` representation of [XCHammerConfig](https://github.com/pinterest/xchammer/blob/master/Sources/XCHammer/XCHammerConfig.swift).

The configuration describes projects that should be generated.

```yaml
# Generates a project containing the target ios-app
targets:
    - "//ios-app:ios-app"

projects:
    "MyProject":
        paths:
            - "**"
```

_See [XCHammerConfig.swift](https://github.com/pinterest/xchammer/blob/master/Sources/XCHammer/XCHammerConfig.swift) for detailed documentation of the format._

_To learn about how Pinterest uses XCHammer with Bazel locally check out [Pinterest Xcode Focused Projects](https://github.com/pinterest/xchammer/blob/master/Docs/PinterestFocusedXcodeProjects.md)._

## Samples

- [a Objective-C iOS app](sample/UrlGet)
- [a Swift iOS app](sample/Tailor) 
- [a Swift macOS app](BUILD.bazel)


### Xcode progress bar integration

XCHammer provides a path to optionally integrate with Xcode's build system and
progress bar.

- Install support for Xcode's progress bar for Xcode 11

```
xchammer install_xcode_build_system
```

- add `--build_event_binary_file=/tmp/bep.bep` to your `.bazelrc`
- make sure Xcode's new build system is enabled


## LLDB integration

Under Swift and clang compilers, the execution root is written into debug info
in object files by default. XCHammer writes an lldbinit file to map this
directory to the source root of source code, so that both breakpoints and
sources work in Xcode.

To make outputs consistent and debuggable across machines, e.g. with remote
caching, it's recommended to use debug info remapping. Debug info remapping is a
technique that simply remaps absolute paths in debug info to a stable location.
LLDB then is able to map these to the source directory, via a
`target.source-map`. By default, these Bazel flags are not configured and
require adding additional flags to the build. Generally, these flags should set
in _your_ `.bazelrc` for every build.

Clang provides debug info remapping via the `-fdebug-prefix-map` flag. For
Objective-C, C, C++, debug info remapping is implemented at the crosstool level.
Configure Bazel to pass these arguments by setting
`--copt="DEBUG_PREFIX_MAP_PWD=."` or providing a custom crosstool.  See setting
up [crosstool
logic](https://github.com/bazelbuild/bazel/blob/master/tools/osx/crosstool/wrapped_clang.cc#L218)
for more info.

Starting with Xcode 10.2, Swift provides debug info remapping via the
`-debug-prefix-map` flag.  `rules_swift` supports the ability to [pass the debug
remapping](https://github.com/bazelbuild/rules_swift/commit/43900104d279fcdffbca2d02dbc550492bf33353).
Simply add `--swiftcopt=-Xwrapped-swift=-debug-prefix-pwd-is-dot` to remap debug
info in Swift.

XCHammer will automatically write a compatible remapping in the `.lldbinit`. Set
`HAMMER_USE_DEBUG_INFO_REMAPPING=YES` via an `xcconfig`. See [XCHammer's BUILD
file](BUILD.bazel), for an example of this.

_Generating a dSYM for development is not recommended due to the performance
hit, and in practice is only required for Instruments.app._

## Development

Please find more info about developing XCHammer in [The XCHammer FAQ](Docs/XCHammerFAQ.md). Pull requests welcome 💖.
