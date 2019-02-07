<p align="left"><img src="logo/horizontal.png" alt="rules_purescript" height="100px"></p>

# Purescript rules for [Bazel][bazel]

Bazel automates building and testing software. It scales to very large
multi-language projects. This project extends Bazel with build rules
for Purescript. Get started building your own project using these rules
wih the [setup script below](#setup).

[bazel]: https://bazel.build/
[bazel-getting-started]: https://docs.bazel.build/versions/master/getting-started.html
[bazel-cli]: https://docs.bazel.build/versions/master/command-line-reference.html
[external-repositories]: https://docs.bazel.build/versions/master/external.html
[nix]: https://nixos.org/nix

## Setup

You'll need [Bazel >= 0.21.0][bazel-getting-started] installed.

Add the following to your `WORKSPACE` file:

```python
# refer to a githash in this repo:
rules_purescript_version = "38abb155c30502c9996925640b9b8e04bd48d974"

# download the archive:
http_archive(
    name = "io_tweag_rules_purescript",
    url  = "https://github.com/tweag/rules_purescript/archive/%s.zip" % rules_purescript_version,
    type = "zip",
    strip_prefix = "rules_purescript-%s" % rules_purescript_version,
)

# rules_purescript uses bazel_skylib
git_repository(
    name = "bazel_skylib",
    remote = "https://github.com/bazelbuild/bazel-skylib.git",
    tag = "0.6.0"
)

# load the purescript rules and functions:
load("@io_bazel_rules_purescript//purescript:purescript.bzl", "purescript_distributions", "purescript_dep")

# register toolchains
register_toolchains(
    "//:purs_darwin_bindist_toolchain",
    "//:purs_linux_bindist_toolchain",
    "//:purs_linux_nixpkgs_toolchain",
)

# get purescript
purescript_distributions()

# add some dependencies:
purescript_dep(
    name = "purescript_console",
    url = "https://github.com/purescript/purescript-console/archive/v4.1.0.tar.gz",
    sha256 = "5b0d2089e14a3611caf9d397e9dd825fc5c8f39b049d19448c9dbbe7a1b595bf",
    strip_prefix = "purescript-console-4.1.0",
)

purescript_dep(
    name = "purescript_effect",
    url = "https://github.com/purescript/purescript-effect/archive/v2.0.0.tar.gz",
    sha256 = "5254c048102a6f4360a77096c6162722c4c4b2449983f26058d75d4e5be9d301",
    strip_prefix = "purescript-effect-2.0.0",
)

purescript_dep(
    name = "purescript_prelude",
    url = "https://github.com/purescript/purescript-prelude/archive/v4.0.1.tar.gz",
    sha256 = "3b69b111875eb2b915fd7bdf320707ed3d22194d71cd51d25695d22ab06ae6ee",
    strip_prefix = "purescript-prelude-4.0.1",
)
```

Also add the following to your project root `BUILD` file:

```python
load("@io_tweag_rules_purescript//purescript:purescript.bzl", "purescript_toolchain")

purescript_toolchain()
```

### Building a Library

In the `BUILD` file of your purescript project you can define a purescript library:

```python
load("@io_bazel_rules_purescript//purescript:purescript.bzl", "purescript_app", "purescript_test")

dependencies = \
    [ "@purescript_console//:pkg"
    , "@purescript_effect//:pkg"
    , "@purescript_prelude//:pkg"
    ]

# Defines an application with default entrypoint (Main.main):
purescript_library(
    name       = "purs-lib",
    visibility = ["//visibility:public"],
    srcs       = glob(["src/**/*.purs"]),
    deps       = dependencies,
)
```

### Bundling

You can currently bundle your project using webpack with the `purescript_bundle` rule however this is untested outside of a private project and is likely to change in the very near future.

### Testing

In the same `BUILD` file, you can define a test module:
```python
purescript_test(
    name = "purs-app-test",
    srcs = glob(["test/**/*.purs"]) + glob(["src/**/*.purs"]),
    deps = dependencies,
)
```

in the `test` directory I've created a module like:

```purescript
module Test.Main where

-- imports omitted

main :: Effect Unit
main = log "Hello test world!"
```

when you run `bazel test` on the `:purs-app-test` project, it should succeed
:tada:

**NOTE:** the default entrypoint for testing is the module `Test.Main` and the
function `main`. But these can be overwritten:

```python
purescript_test(
    name          = "purs-app-test",
    srcs          = glob(["test/**/*.purs"]) + glob(["src/**/*.purs"]),
    deps          = dependencies,
    main_module   = "MyMainTest.Whatever"
    main_function = "myFun"
)

```console
$ bazel build //...    # Build all targets
$ bazel test //...     # Run all tests
```

You can learn more about Bazel's command line
syntax [here][bazel-cli]. Common [commands][bazel-cli-commands] are
`build`, `test`, `run` and `coverage`.

## For `rules_purescript` developers

### Saving common command-line flags to a file

If you find yourself constantly passing the same flags on the
command-line for certain commands (such as `--host_platform` or
`--compiler`), you can augment the [`.bazelrc`](./.bazelrc) file in
this repository with a `.bazelrc.local` file. This file is ignored by
Git.

### Reference a local checkout of `rules_purescript`

When you develop on `rules_purescript`, you usually do it in the context
of a different project that has `rules_purescript` as a `WORKSPACE`
dependency, like so:

```
http_archive(
    name = "io_tweag_rules_purescript",
    strip_prefix = "rules_purescript-" + version,
    sha256 = …,
    urls = …,
)
```

To reference a local checkout instead, use the
[`--override_repository`][override_repository] command line option:

```
bazel build/test/run/sync \
  --override_repository io_tweag_rules_purescript=/path/to/checkout
```

If you don’t want to type that every time, [temporarily add it to
`.bazelrc`][bazelrc].

[override_repository]: https://docs.bazel.build/versions/master/command-line-reference.html#flag--override_repository
[local_repository]: https://docs.bazel.build/versions/master/be/workspace.html#local_repository
[bazelrc]: https://docs.bazel.build/versions/master/best-practices.html#bazelrc


### Formatting

Skylark code in this project is formatted according to the output of
[buildifier]. You can check that the formatting is correct using:

```
$ bazel run //:buildifier
```

If tests fail then run the following to fix the formatting:

```
$ bazel run //:buildifier-fix
```

[buildifier]: https://github.com/bazelbuild/buildtools/tree/master/buildifier
