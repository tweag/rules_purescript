"""Rules for purescript"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_skylib//lib:paths.bzl", "paths")
load(":toolchain.bzl",
     _purescript_toolchain = "purescript_toolchain",
     _purescript_distributions = "purescript_distributions",
     _purs_toolchain = "purs_toolchain",
)

purescript_toolchain = _purescript_toolchain
purescript_distributions = _purescript_distributions
purs_toolchain = _purs_toolchain

_purescript_dep_build_content = """
package(default_visibility = ["//visibility:public"])
load("@io_tweag_rules_purescript//purescript:purescript.bzl", "purescript_library")

purescript_library(
    name = "pkg",
    srcs = glob(["src/**/*.purs"]) + glob(["src/**/*.js"]),
    deps = [%s],
)
"""

def purescript_dep(name, url, sha256, strip_prefix, deps = [], patches = []):
    http_archive(
        name = name,
        urls = [url],
        sha256 = sha256,
        strip_prefix = strip_prefix,
        build_file_content = _purescript_dep_build_content % ",".join([repr(d) for d in deps]),
        patches = patches,
    )

def drop_til_initcaps(l):
    drop_at = None
    for (idx, part) in enumerate(l):
        if part[0].upper() == part[0] and not drop_at:
            drop_at = idx

    if not drop_at:
        drop_at = 0

    return l[drop_at:]

# We need a good way of figuring out the module name just by looking at the file path.
#   I don't think there is one.
def output_file(ctx, name, src, outdir):
    components = paths.split_extension(src.short_path)[0].split("/")
    module_parts = drop_til_initcaps(components)

    path = paths.join(
        outdir.basename,
        ".".join(module_parts),
        name,
    )
    return ctx.actions.declare_file(path, sibling = outdir)

def _path_above_dir(path, dir):
  parts = path.split("/")
  topParts = parts[(parts.index(dir))+1:]
  return "/".join(topParts)

def _purescript_library(ctx):
    purs = ctx.toolchains["@io_tweag_rules_purescript//purescript:toolchain_type"].purs_info.purs_path
    srcs = ctx.files.srcs
    deps = ctx.attr.deps
    zipper = ctx.executable._zipper
    outdir = ctx.actions.declare_directory("lib_output")

    ps_dep_srcs = depset(transitive = [dep[OutputGroupInfo].srcs for dep in deps])
    ps_dep_outputs = depset(transitive = [dep[OutputGroupInfo].outputs for dep in deps])

    deps_zip = ctx.actions.declare_file("deps.zip")
    zipPaths = ["%s=%s" % (_path_above_dir(p.path, outdir.basename), p.path) for p in ps_dep_outputs.to_list()]

    # We need to create a single zip file of all the dependencies'
    # precompiled outputs, so we can pass them all through as a single
    # argument..

    ctx.actions.run_shell(
        inputs = ps_dep_outputs.to_list(),
        tools = [ctx.executable._zipper],
        command = """
        set -e

        if [ $# -gt 1 ]
        then
          echo Creating {deps_zip}
          {zipper} c {deps_zip} $@
        else
          echo Simulating
          touch empty
          {zipper} c {deps_zip} empty=empty
        fi
        """.format(zipper = ctx.executable._zipper.path,
                   deps_zip = deps_zip.path),
        arguments = zipPaths,
        outputs = [deps_zip],
    );

    # Build this lib.
    outputs = []
    for src in srcs:
        if src.extension == "purs":
            outputs += [output_file(ctx, "index.js", src, outdir)]
            outputs += [output_file(ctx, "externs.json", src, outdir)]

        if src.extension == "js":
            outputs += [output_file(ctx, "foreign.js", src, outdir)]

    ctx.actions.run_shell(
        inputs = srcs + ps_dep_srcs.to_list() + [deps_zip],
        tools = [zipper, purs],
        command = """
          set -e

          if [ -s {output} ]
          then
              {zipper} x {deps_zip} -d {output}
              chmod -R +w ./*
          fi

          {purs} compile --output {output} $@
        """.format(zipper = ctx.executable._zipper.path,
                   purs = purs.path,
                   output = outdir.path,
                   deps_zip = deps_zip.path,
                   ),
        arguments = [
            s.path
            for s
            in srcs + ps_dep_srcs.to_list()
            if s.extension == "purs"
        ],
        outputs = outputs + [outdir],
    )

    output_zip = ctx.actions.declare_file("output.zip")
    outputZipPaths = ["%s=%s" % (_path_above_dir(p.path, outdir.basename), p.path) for p in outputs]
    ctx.actions.run_shell(
      inputs = outputs,
      tools = [zipper],
      command = "{zipper} c {output_zip} $@".format(zipper = ctx.executable._zipper.path, output_zip = output_zip.path),
      arguments = outputZipPaths,
      outputs = [output_zip],
    )

    return [
        DefaultInfo(files = depset(srcs + outputs)),
        OutputGroupInfo(
            srcs = depset(srcs, transitive = [ps_dep_srcs]),
            outputs = depset(outputs, transitive = [ps_dep_outputs]),
            output_zip = [output_zip, deps_zip],
        ),
    ]

purescript_library = rule(
    implementation = _purescript_library,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "deps": attr.label_list(
            default = [],
        ),
        "_zipper": attr.label(executable=True, cfg="host", default=Label("@bazel_tools//tools/zip:zipper"), allow_files=True)
    },
    toolchains = ["@io_tweag_rules_purescript//purescript:toolchain_type"]
)

def _trim_package_node_modules(package_name):
    # trim a package name down to its path prior to a node_modules
    # segment. 'foo/node_modules/bar' would become 'foo' and
    # 'node_modules/bar' would become ''
    segments = []
    for n in package_name.split("/"):
        if n == "node_modules":
            break
        segments += [n]
    return "/".join(segments)

def _purescript_bundle(ctx):
    webpack = ctx.executable.webpack
    zipper = ctx.executable._zipper
    srcs = ctx.files.srcs
    dep_outputs = depset(transitive = [dep[OutputGroupInfo].outputs for dep in ctx.attr.deps])
    output_zip = depset(transitive = [dep[OutputGroupInfo].output_zip for dep in ctx.attr.deps])
    files = [z for z in output_zip.to_list()] + [p for p in dep_outputs.to_list()] + [f for f in srcs] + [ctx.file.config] + [ctx.file.entry] + ctx.files.node_modules
    output = ctx.actions.declare_file("dist.zip")

    node_modules_root = "/".join([f for f in [
        ctx.attr.node_modules.label.workspace_root,
        _trim_package_node_modules(ctx.attr.node_modules.label.package),
        "node_modules",
    ] if f])

    ctx.actions.run_shell(
        inputs = files,
        tools = [webpack, zipper],
        command = """
        set -e
        export WORKSPACE=$(pwd)
        export PROJECT_DIR=$(dirname {build_file})
        zips=({zips})
        cd $PROJECT_DIR
        for f in "${{zips[@]}}"; do
          $WORKSPACE/{zipper} x $WORKSPACE/$f -d ./deps
        done
        ln -s $WORKSPACE/{node_modules} .
        $WORKSPACE/{webpack} --config $(basename {config}) --display errors-only
        for file in $(find dist -type f); do
          files_to_zip="$files_to_zip${{file#dist/}}=$file "
        done
        $WORKSPACE/{zipper} c $WORKSPACE/{output} $files_to_zip
        """.format(webpack = webpack.path,
                   config = ctx.file.config.path,
                   entry = ctx.file.entry.path,
                   node_modules = node_modules_root,
                   zipper = zipper.path,
                   zips = " ".join([z.path for deps in [dep[OutputGroupInfo].output_zip.to_list() for dep in ctx.attr.deps] for z in deps]),
                   output = output.path,
                   build_file = ctx.build_file_path,
                   ),
        arguments = [],
        outputs = [output],
    );
    return [DefaultInfo(executable = output)]

purescript_bundle = rule(
  implementation = _purescript_bundle,
  attrs = {
    "deps": attr.label_list(
      default = [],
    ),
    "srcs": attr.label_list(
        allow_files = True,
    ),
    "config": attr.label(allow_single_file = True,),
    "entry": attr.label(allow_single_file = True,),
    "node_modules": attr.label(allow_files = True,),
    "webpack": attr.label(
        allow_files = True,
        executable = True,
        cfg = "host",
        # default = "@webpack",
    ),
    "_zipper": attr.label(executable=True, cfg="host", default=Label("@bazel_tools//tools/zip:zipper"), allow_files=True)
  },
  toolchains = ["@io_tweag_rules_purescript//purescript:toolchain_type"]
)

def _purescript_test(ctx):
    purs = ctx.toolchains["@io_tweag_rules_purescript//purescript:toolchain_type"].purs_info.purs_path
    srcs = ctx.files.srcs
    deps = ctx.attr.deps
    zipper = ctx.executable._zipper

    outdir = ctx.actions.declare_directory("test_output")
    ps_dep_srcs = depset(transitive = [dep[OutputGroupInfo].srcs for dep in deps])
    ps_dep_outputs = depset(transitive = [dep[OutputGroupInfo].outputs for dep in deps])
    runtime_deps = depset(transitive = [dep[DefaultInfo].files for dep in ctx.attr.runtime_deps])

    deps_zip = ctx.actions.declare_file("test_deps.zip")
    zipPaths = ["%s=%s" % (_path_above_dir(p.path, "lib_output"), p.path) for p in ps_dep_outputs.to_list()]

    # We need to create a single zip file of all the dependencies'
    # precompiled outputs, so we can pass them all through as a single
    # argument..

    ctx.actions.run_shell(
        inputs = ps_dep_outputs.to_list(),
        tools = [ctx.executable._zipper],
        command = """
        set -e

        if [ $# -gt 1 ]
        then
          echo Creating {deps_zip}
          {zipper} c {deps_zip} $@
        else
          echo Simulating
          touch empty
          {zipper} c {deps_zip} empty=empty
        fi
        """.format(zipper = ctx.executable._zipper.path,
                   deps_zip = deps_zip.path),
        arguments = zipPaths,
        outputs = [deps_zip],
    );

    # Build this lib.
    outputs = []
    for src in srcs:
        if src.extension == "purs":
            outputs += [output_file(ctx, "index.js", src, outdir)]
            outputs += [output_file(ctx, "externs.json", src, outdir)]

        if src.extension == "js":
            outputs += [output_file(ctx, "foreign.js", src, outdir)]

    ctx.actions.run_shell(
        inputs = srcs + ps_dep_srcs.to_list() + [deps_zip],
        tools = [purs, zipper],
        command = """
          set -e

          if [ -s {output} ]
          then
              {zipper} x {deps_zip} -d {output}
              chmod -R +w ./*
          fi

          {purs} compile --output {output} $@
        """.format(zipper = ctx.executable._zipper.path,
                   purs = purs.path,
                   output = outdir.path,
                   deps_zip = deps_zip.path,
                   ),
        arguments = [
            s.path
            for s
            in srcs + ps_dep_srcs.to_list()
            if s.extension == "purs"
        ],
        outputs = outputs + [outdir],
    )

    index = output_file(ctx, "index.js", ctx.file.main_module, outdir)

    ctx.actions.write(
        output = ctx.outputs.executable,
        content = """
          set -e
          NODE_PATH=./external/npm/node_modules {node} {index}
        """.format(node = ctx.executable.node.path,
                   index = index.path.split(ctx.bin_dir.path + "/",1).pop(),
                   bin_dir = ctx.bin_dir.path,
          ),
    )

    runfiles = ctx.runfiles(files = outputs + [ctx.executable.node] + ps_dep_outputs.to_list() + runtime_deps.to_list())
    return [DefaultInfo(executable = ctx.outputs.executable, runfiles = runfiles)]

purescript_test = rule(
    implementation = _purescript_test,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(),
        "runtime_deps": attr.label_list(),
        "main_module": attr.label(
            default = "test/Test/Main.purs",
            allow_single_file = True,
        ),
        "main_function": attr.string(
            default = "main",
        ),
        "compiler_flags": attr.string_list(
            default = [],
        ),
        "_zipper": attr.label(executable=True, cfg="host", default=Label("@bazel_tools//tools/zip:zipper"), allow_files=True),
        "node": attr.label(
            allow_files = True,
            executable = True,
            cfg = "host",
        ),
    },
    test = True,
    toolchains = ["@io_tweag_rules_purescript//purescript:toolchain_type"],
)
