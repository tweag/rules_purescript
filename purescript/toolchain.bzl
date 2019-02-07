load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

_DARWIN_BINDIST = {
    "url": "https://github.com/purescript/purescript/releases/download/v0.11.7/macos.tar.gz",
    "sha256": "d8caa11148f8a9a2ac89b0b0c232ed8038913576e46bfc7463540c09b3fe88ce",
}

_LINUX_BINDIST = {
    "url": "https://github.com/purescript/purescript/releases/download/v0.11.7/linux64.tar.gz",
    "sha256": "fd8b96240e9485f75f21654723f416470d8049655ac1d82890c13187038bfdde",
}

_DEFAULT_PURS_PKG_STRIP_PREFIX = "purescript"

PursInfo = provider(
    doc = "Information about how to invoke purs.",
    fields = ["purs_path"],
)

def _purs_toolchain_impl(ctx):
    purescript_binaries = {}
    for file in ctx.files.tools:
        if "purs" == paths.split_extension(file.basename)[0]:
            purescript_binaries["purs"] = file
    purs = purescript_binaries["purs"]
    purs_info = PursInfo(
        purs_path = purs,
    )
    return [platform_common.ToolchainInfo(
        name = "darwin_nixpkgs",
        purs_info = PursInfo(purs_path = purs)
        )]

purs_toolchain = rule(
    implementation = _purs_toolchain_impl,
    attrs = {
        "tools": attr.label(
            doc = "Purescript purs and tools that come with it",
            mandatory = True
        ),
    },
)

purs_bindist_buildfile = '''
package(default_visibility = ["//visibility:public"])
filegroup(
   name = "purs_bindist_filegroup",
   srcs = glob(["*"]),
)'''

def purescript_distributions(path=None, name = "purs"):
    http_archive(
      name = "purs_bindist_linux",
      urls = [_LINUX_BINDIST["url"]],
      sha256 = _LINUX_BINDIST["sha256"],
      strip_prefix = _DEFAULT_PURS_PKG_STRIP_PREFIX,
      build_file_content = purs_bindist_buildfile,
    )

    http_archive(
      name = "purs_bindist_darwin",
      urls = [_DARWIN_BINDIST["url"]],
      sha256 = _DARWIN_BINDIST["sha256"],
      strip_prefix = _DEFAULT_PURS_PKG_STRIP_PREFIX,
      build_file_content = purs_bindist_buildfile,
    )
    if path:
       native.new_local_repository(
           name = "purs_nixpkgs_linux",
           path = path,
           build_file_content = '''
package(default_visibility = ["//visibility:public"])

filegroup(
   name = "purs_bindist_filegroup",
   srcs = glob(["bin/*"]),
)''')

# TODO Refactor this
def purescript_toolchain():
    """
        Defines 3 purescript toolchains labeled `purs_darwin_bindist`,
        `purs_linux_bindist` and `purs_linux_nixpkgs`.

        You need to call at least once `purescript_toolchain` somewhere
        in your `BUILD` files.

        Once called, you'll need to regiter these toolchains using the
        `register_toolchains` builtin function in your `WORKSPACE`.
    """
    purs_toolchain(
        name = "purs_darwin_bindist",
        tools = "@purs_bindist_darwin//:purs_bindist_filegroup",
    )

    purs_toolchain(
        name = "purs_linux_bindist",
        tools = "@purs_bindist_linux//:purs_bindist_filegroup",
    )

    purs_toolchain(
        name = "purs_linux_nixpkgs",
        tools = "@purs_nixpkgs_linux//:purs_bindist_filegroup",
    )

    native.toolchain(
        name = "purs_linux_bindist_toolchain",
        exec_compatible_with = [
            "@bazel_tools//platforms:x86_64",
            "@bazel_tools//platforms:linux",
        ],
        target_compatible_with = [
            "@bazel_tools//platforms:x86_64",
            "@bazel_tools//platforms:linux",
        ],
        toolchain = ":purs_linux_bindist",
        toolchain_type = "@io_tweag_rules_purescript//purescript:toolchain_type",
    )

    native.toolchain(
        name = "purs_linux_nixpkgs_toolchain",
        exec_compatible_with = [
            "@bazel_tools//platforms:x86_64",
            "@bazel_tools//platforms:linux",
            "@io_tweag_rules_purescript//purescript/platforms:nixos",
        ],
        target_compatible_with = [
            "@bazel_tools//platforms:x86_64",
            "@bazel_tools//platforms:linux",
            "@io_tweag_rules_purescript//purescript/platforms:nixos",
        ],
        toolchain = ":purs_linux_nixpkgs",
        toolchain_type = "@io_tweag_rules_purescript//purescript:toolchain_type",
    )

    native.toolchain(
        name = "purs_darwin_bindist_toolchain",
        exec_compatible_with = [
            "@bazel_tools//platforms:osx",
            "@bazel_tools//platforms:x86_64",
        ],
        target_compatible_with = [
            "@bazel_tools//platforms:osx",
            "@bazel_tools//platforms:x86_64",
        ],
        toolchain = ":purs_darwin_bindist",
        toolchain_type = "@io_tweag_rules_purescript//purescript:toolchain_type",
    )
