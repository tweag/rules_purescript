package(default_visibility = ["//visibility:public"])

load("@com_github_bazelbuild_buildtools//buildifier:def.bzl", "buildifier")

# Run this to check for errors in BUILD files.
buildifier(
    name = "buildifier",
    mode = "check",
)

# Run this to fix the errors in BUILD files.
buildifier(
    name = "buildifier-fix",
    mode = "fix",
    verbose = True,
)
