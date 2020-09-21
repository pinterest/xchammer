# XCHammer Overview

XCHammer generates Xcode projects from a [Bazel](https://bazel.build/)
Workspace. This document is meant to supplement the [README](#README.md), a
minimal getting started reference.

## Table of Contents


   * [XCHammer Overview](#xchammer-overview)
      * [Table of Contents](#table-of-contents)
      * [Introduction](#introduction)
      * [Xcode project rule](#xcode-project-rule)
      * [Comand line interface](#comand-line-interface)
      * [Sources Aspect](#sources-aspect)
      * [Project Configuration Aspect](#project-configuration-aspect)
      * [Sources Aspect](#sources-aspect-1)
      * [Xcode project generation](#xcode-project-generation)
      * [Examples of common problems and how they were fixed](#examples-of-common-problems-and-how-they-were-fixed)
         * [Xcode project generation problem and solution](#xcode-project-generation-problem-and-solution)
         * [Normalizing Bazel configuration problem and solution](#normalizing-bazel-configuration-problem-and-solution)
         * [Too many files in Xcode and indexer performance](#too-many-files-in-xcode-and-indexer-performance)


## Introduction

XCHammer is a Bazel
[rule](https://docs.bazel.build/versions/master/skylark/rules.html) and command
line program that generates an Xcode project by virtue of standard Bazel
interfaces, [Tulsi](https://github.com/bazelbuild/tulsi), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

It traverses the Bazel build graph with an
[aspect](https://docs.bazel.build/versions/master/skylark/aspects.html) to
gather information about the build graph and passes the information to a
[rule](https://docs.bazel.build/versions/master/skylark/rules.html), which then
writes out an project via XcodeGen. Because of it's prolific code reuse, it's a
quite simple piece of code that ended up being very small on disk. The core
source code is just over a couple thousand LOC of swift excluding dependencies.

That XCHammer reuses robust open source code is an implementation detail and not
exposed in any way to users. XCHammer relies on much functionality from Tulsi.
First, Tulsi's code is responsible for driving Bazel with the build script and
and copying artifacts into DerivedData. Finally it uses the the Tulsi aspect to
gather information about a project.

For the backend, XCHammer uses XcodeGen as an Xcode project generator. After
reading in the Bazel build graph with Tulsi, XcodeGen structs are allocated.
Finally, it uses the dependency, xcodeproj, to write an Xcode project out to
disk.

Because these projects are fundamental to the XCHammer, contributors to XCHammer
often improve XcodeGen, Tulsi, Bazel, and community rules. By reusing Tulsi and
XcodeGen, XCHammer is overall easier to maintain and update across Bazel and
Xcode updates.

Please see the document [Bazel for iOS
developers](BazelForiOSDevelopers.md) to learn more about the common
interfaces that XCHammer uses. The segment [Xcode Project
generators](BazelForiOSDevelopers.md#generated-xcode-projects) provides an
high level overview of such an architecture and how an aspects and rule fit
together with Bazel and how Xcode is integrated with Bazel.


## Xcode project rule

The `xcode_project` rule is the core rule to build Xcode projects. Through this
rule, it only generates an Xcode project when the inputs change.

```
load("@xchammer_resources//:xcodeproject.bzl", "xcode_project")
xcode_project(
    name = "MyProject",
    targets = [ "//ios-app:ios-app" ],
    paths = [ "**" ],
)
```

The rule `xcode_project` invokes the [XCHammer
binary](../Sources/XCHammer/main.swift) with arguments including a json
representation of [XCHammerConfig](../Sources/XCHammer/XCHammerConfig.swift) and a
json represention of
[XcodeProjectRuleInfo](../Sources/XCHammer/XCHammerGenerateOptions.swift). Inside
of the main function is where the main logic of generating an Xcode project
exists. 

## Comand line interface

Originally, XCHammer exposed a command line program similiar to Tulsi. As
developers were spending a lot of waiting for generating Xcode projects, a
mechanism to noop project generation was added external to Bazel.

_While this mechanism is quite functional, ideally it will be removed in favor
of the rule only_ 

## Sources Aspect

The rule, [`xcode_project`](../BazelExtensions/xcodeproject.bzl) accepts 2
different aspects for the users specified target. 

First, and most involved, is the `tulsi_sources_aspect`. This aspect is used to
traverse the build graph and then collect information about each target. While
collecting information about each target, it outputs the information into a
json reprsentation that XCHammer reads in with the standard swift
JSONSerializaton parsing system.

## Project Configuration Aspect

In addition to collecting metadata about each rule, it collects ad-hoc Xcode
configuration data that each target needs. For basic usage, the `xcode_project`
rule in instantiated quite simply, for example:
```
load("@xchammer_resources//:xcodeproject.bzl", "xcode_project")
xcode_project(
    name = "MyProject",
    targets = [ "//ios-app:ios-app" ],
    paths = [ "**" ],
)
```

Putting everything into a single config file became ineffective when projects
grew in complexity and features. The main issue was having to set many kinds of
options in Xcode for each target. For example, a project may have different
environment variables in the scheme and vary on each target. Another example,
is [bolting on xcode project
instrumentation](PinterestFocusedXcodeProjects.md) in order to track local
build times in Xcode with statsd. At one point, the `XCHammerConfig` was too
complex and unmaintainable. This aspect was created to setup Xcode target
metadata adjacent to the rules.

For example, snapshot tests need an un-hermtic environment variable while
running in Xcode, and the variable `ENABLE_RECORD_MODE` to flip it on.

```
load(
    "@xchammer_resources//:xchammerconfig.bzl",
    "environment_variable",
    "scheme_action_config",
)
snapshot_env = [
    environment_variable(
        value = "$(SRCROOT)/Images.bundle",
        variable = "FB_REFERENCE_IMAGE_DIR",
    ),
    environment_variable(
        enabled = False,
        value = "YES",
        variable = "ENABLE_RECORD_MODE",
    ),
]

snapshot_tests_target_config = target_config(
    scheme_config = {
        "Run": scheme_action_config(
            environment_variables = snapshot_env,
        ),
        "Build": default_scheme_config["Build"],
    },
    xcconfig_overrides = {},
)

declare_target_config(
    name = "XcodeTargetConfig",
    config = snapshot_tests_target_config,
    visibility = ["//visibility:public"],
)

ios_unit_test(
   name = "SnapshotTests",
   deps = [":Lib", ":XcodeTargetConfig"]
)

```

The aspect traverses the build graph and looks for rules which which have
associated configuration metadata `declare_target_config`, and
then it merges them into a single JSON file which is read by XCHammer and used
during generation. Overall, the result is cleaner configuration adjacent to
target definition.

## Sources Aspect

In addition to the other aspects, a third aspect exists. The
`xcode_build_sources_aspect` extracts generated source files from a project.
The aspect traverse the dependency graph, and install sources into
`xchammer-includes`. In the original design of XCHammer, it read files directly
from `bazel-genfiles`, but that directory is unstable and changes from build to
build. It uses `xchammer-includes` to stablize the indexer accross Bazel
invocations. Note, that this has the side effect that material inside of
`xchammer-includes` often has artifacts that are no longer part of the build.
The same issue exists with `bazel-genfiles` and the directory
`xchammer-includes` may be manually deleted from time to time along with
`DerivedData`

## Xcode project generation

XCHammer relies on the robust open source library
[XcodeGen](https://github.com/yonaskolb/XcodeGen).  XcodeGen handles the legwork
of generating `PBXObject`s that represent the Xcode project. By splitting out
most business logic into aspects, rules, Tulsi, and XcodeGen, the logic of
XCHammer excludes much complexity. This allows developers of XCHammer only to
focus on the problem at hand. By using XcodeGen, it's straight forward to
generate an Xcode project that _just works_ with or without Bazel.

For information about how Xcode runs Bazel builds, see [Xcode Project
generators](BazelForiOSDevelopers.md#generated-xcode-projects)

## Examples of common problems and how they were fixed

XCHammer and Bazel are the solution to many iOS developer problems. In addition
to being the solution, there's a handful of problems in such tools. This
segment contains a mix of both problems and solutions.

### Xcode: establishing configuration norms - problem and solution

In traditional Xcode usage, developers are able to change Xcode projects and
Xcode configuration files and there is no defaults enforced. 

In vanilla Bazel usage, a similar problem exists  when the user is allowed to
specificy `copts`. Therefore, a simple system of macros is implemented in order
to prevent users from configuring `copts` in an unexpected way. See the segment
[marcos](BazelForiOSDevelopers.md#macros) for a complete listing.
Recently, there has been work on Bazel to extract the native rules. Note, that
the Bazel toolchain is orthogonal to using macros to wrap rules
[rules_cc](https://github.com/bazelbuild/rules_cc).


### Xcode: Xcode project generation - problem and solution

Traditionally, Xcode projects are checked into the repo along with the source
code. This results in frequent, painful, merges and hard to review PRs. With
XCHammer, Xcode projects are generated on the developer's machine. By generating
transient projects locally, merge conflicts don't slow down development.
Generated projects make it easier to review and reason about configuration
changes in readable BUILD and .bzl files. 

The XCHammer tool one the solution to project generation. Additionally, it
solves the problem of being able to build the app with Xcode.


### Xcode: too many files in Xcode and indexer performance - problem and solution

When Xcode projects grown in size and scope, the IDE experience starts to
degrade. By default Xcode ends up indexing the entire source tree which hogs CPU
resources and slows down autocomplete. The document, [Pinterest Focused Xcode
Projects](PinterestFocusedXcodeProjects.md) explains how Bazel and XCHammer
are used to solve this problem and reduce the load by orders of magnitude.

