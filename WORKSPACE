workspace(name = "io_tweag_rules_purescript")
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

git_repository(
    name = "bazel_skylib",
    remote = "https://github.com/bazelbuild/bazel-skylib.git",
    tag = "0.6.0"
)

# For buildifier

http_archive(
    name = "io_bazel_rules_go",
    sha256 = "8be57ff66da79d9e4bd434c860dce589195b9101b2c187d144014bbca23b5166",
    strip_prefix = "rules_go-0.16.3",
    urls = ["https://github.com/bazelbuild/rules_go/archive/0.16.3.tar.gz"],
)

http_archive(
    name = "com_github_bazelbuild_buildtools",
    sha256 = "c730536b703b10294675743579afa78055d3feda92e8cb03d2fb76ad97396770",
    strip_prefix = "buildtools-0.20.0",
    urls = ["https://github.com/bazelbuild/buildtools/archive/0.20.0.tar.gz"],
)
# A repository that generates the Go SDK imports, see ./tools/go_sdk/README
local_repository(
    name = "go_sdk_repo",
    path = "tools/go_sdk",
)

load("@go_sdk_repo//:sdk.bzl", "gen_imports")

gen_imports(name = "go_sdk_imports")

load("@go_sdk_imports//:imports.bzl", "load_go_sdk")

load_go_sdk()

load("@com_github_bazelbuild_buildtools//buildifier:deps.bzl", "buildifier_dependencies")

buildifier_dependencies()
