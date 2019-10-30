# Load the sources aspect from Tulsi
load("@xchammer-Tulsi//src/TulsiGenerator/Bazel:tulsi/tulsi_aspects.bzl", "tulsi_sources_aspect", "TulsiSourcesAspectInfo")
load("//tools:xchammerconfig.bzl", "xchammer_config", "gen_xchammer_config", "project_config")

def _xcode_project_impl(ctx):
    artifacts = []
    for dep in ctx.attr.targets:
        for a in dep[OutputGroupInfo].tulsi_info.to_list():
            artifacts.append(a)

    xchammer_info_json = ctx.actions.declare_file("xchammer_info.json")


    xchammer_info=struct(
        tulsiinfos=[a.path for a in artifacts],
        # This is used by bazel_build_settings.py and replaced by
        # install_xcode_project.
        execRoot="__BAZEL_EXEC_ROOT__",

        # This rule is for the actual _imp. We want XCHammer to run the install
        # target.
        # TODO(V2): for workspace mode, we need a way to invoke this to include all
        # targets
        bazelTargets=[str(ctx.label)[:-5]],

        xchammerPath=ctx.attr.xchammer if ctx.attr.xchammer[0] == "/" else "$SRCROOT/" + ctx.attr.xchammer
    )
    ctx.file_action(
        content=xchammer_info.to_json(),
        output=xchammer_info_json
    )

    # If we're doing a source build of XCHammer then do so
    # this is intended for development of XCHammer only
    xchammer_command = []
    if ctx.attr.xchammer_bazel_build_target:
        xchammer_files = ctx.attr.xchammer_bazel_build_target.files.to_list()
        xchammer_zip = xchammer_files[0].path
        xchammer_command.append(
            "unzip -o " + xchammer_zip  + " -d $(dirname $(readlink $PWD/WORKSPACE))/;")
    else:
        xchammer_files = []

    # TODO(V2): handle absolute paths here
    xchammer_command.append(
         ctx.attr.xchammer + "/Contents/MacOS/xchammer")

    xchammer_command.extend([
        "generate_v2",

        ctx.attr.config.files.to_list()[0].path,

        # Write the xcode project into the bin_dir.
        # In order to keep this hermetic, the project must be installed out of band
        # or in another non-hermetic rule which depends on this
        "--workspace_root",
        ctx.bin_dir.path,

        "--bazel",
        ctx.attr.bazel if ctx.attr.bazel[0] == "/" else "\$SRCROOT/" + ctx.attr.bazel,

        "--xcode_project_rule_info",
        xchammer_info_json.path
    ])

    ctx.actions.run_shell(
        mnemonic="XcodeProject",
        inputs=artifacts + ctx.attr.config.files.to_list() + [xchammer_info_json] + xchammer_files,
        command=" ".join(xchammer_command),
        outputs=[ctx.outputs.out]
    )

_xcode_project = rule(
    implementation = _xcode_project_impl,
    attrs = {
        "targets" : attr.label_list(aspects = [tulsi_sources_aspect]),
        "project_name" : attr.string(),
        "bazel" : attr.string(default="Bazel"),
        "config" : attr.label(mandatory=True, allow_single_file=True),
        "xchammer" : attr.string(mandatory=True),

        # This is used as a development option only
        "xchammer_bazel_build_target" : attr.label(mandatory=False),
    },
    outputs={"out": "%{project_name}.xcodeproj"}
)


def _install_xcode_project_impl(ctx):
    xcodeproj = ctx.attr.xcodeproj.files.to_list()[0]
    output_proj = "$(dirname $(readlink $PWD/WORKSPACE))/" + xcodeproj.basename
    command = [
        "ditto " + xcodeproj.path + " " + output_proj,
        "sed -i '' \"s,__BAZEL_EXEC_ROOT__,$PWD,g\" " + output_proj + "/XCHammerAssets/bazel_build_settings.py",
        # This is kind of a hack for reference bazel relative to the source
        # directory, as bazel_build_settings.py doesn't sub Xcode build
        # settings.
        "sed -i '' \"s,\$SRCROOT,$(dirname $(readlink $PWD/WORKSPACE)),g\" " + output_proj + "/XCHammerAssets/bazel_build_settings.py",
        "ln -sf $PWD/external $(dirname $(readlink $PWD/WORKSPACE))/external",
        "echo \"" + output_proj + "\" > " + ctx.outputs.out.path
    ]
    ctx.actions.run_shell(
        inputs=ctx.attr.xcodeproj.files,
        command=";".join(command),
        use_default_shell_env=True,
        outputs=[ctx.outputs.out]
    )


_install_xcode_project = rule(
    implementation = _install_xcode_project_impl,
    attrs = {
        "xcodeproj" : attr.label(mandatory=True),
    },
    outputs={"out": "%{name}.dummy"}
)

def xcode_project(**kwargs):
    """ Generate an Xcode project

    name: attr.string name of the target

    targets:  attr.label_list

    bazel: attr.string path to Bazel used during Xcode builds

    xchammer: attr.string path to xchammer

    project_name: (optional)

    target_config: (optional) struct(target_config)
    
    project_config: (optional) struct(target_config)
    """
    proj_args = kwargs
    rule_name = kwargs["name"]

    if not kwargs.get("project_name"):
        proj_args["project_name"] = kwargs["name"]

    # Build an XCHammer config Based on inputs
    targets_attr = [str(t) for t in kwargs.get("targets")]
    target_config_attr = proj_args.pop("target_config") if proj_args.get("target_config") else None
    project_config_attr = proj_args.pop("project_config") if proj_args.get("project_config") else project_config(paths = ["**"])

    gen_xchammer_config(
        name=rule_name + "_xchammer_config",
        config=xchammer_config(
            target_config=target_config_attr,
            projects={ proj_args["project_name"] : project_config_attr },
            targets=targets_attr,
        ),
    )

    # XCHammer development only
    xchammer_target = "//:xchammer"
    if xchammer_target in targets_attr:
        proj_args["xchammer_bazel_build_target"] = xchammer_target

    proj_args["config"] = rule_name + "_xchammer_config"
    proj_args["name"] =  rule_name + "_impl"

    _xcode_project(**proj_args)

    # Note: _xcode_project does the hermetic, reproducible bits
    # and then, we install this xcode project into the root directory.
    _install_xcode_project(
        name=rule_name,
        xcodeproj=kwargs["name"])
