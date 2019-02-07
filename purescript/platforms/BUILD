constraint_setting(name = "distro")
constraint_value(
    name = "nixos",
    constraint_setting = ":distro",
    visibility = ["//visibility:public"],
)

platform(
    name = "linux_x86_64_nixpkgs",
    constraint_values = [
        # XXX using the platform names defined here results in a graph
        # cycle for some reason.
        "@bazel_tools//platforms:x86_64",
        "@bazel_tools//platforms:linux",
        ":nixos",
    ],
    visibility = ["//visibility:public"],
)
