"""API for declaring a PMD lint aspect that visits java_library rules.

Typical usage:

First, call the `fetch_pmd` helper in `WORKSPACE` to download the zip file.
Alternatively you could use whatever you prefer for managing Java dependencies, such as a Maven integration rule.

Next, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

```starlark
java_binary(
    name = "spotbugs",
    main_class = "edu.umd.cs.findbugs.LaunchAppropriateUI",
    runtime_deps = ["@com_github_spotbugs_spotbugs"],
)
```

Finally, declare an aspect for it, typically in `tools/lint/linters.bzl`:

```starlark
load("@aspect_rules_lint//lint:spotbugs.bzl", "spotbugs_aspect")

spotbugs = spotbugs_aspect(
    binary = "@@//tools/lint:spotbugs",
    rulesets = ["@@//:sp.xml"],
)
```
"""

#load("@rules_jvm_external//:defs.bzl", "maven_install")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "filter_srcs", "noop_lint_action", "output_files", "should_visit")

_MNEMONIC = "AspectRulesLintSpotbugs"

def spotbugs_action(ctx, executable, srcs, exclude_filter, stdout, exit_code = None, options = []):
    """Run PMD as an action under Bazel.

    Based on https://docs.pmd-code.org/latest/pmd_userdocs_installation.html#running-pmd-via-command-line

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the the PMD program
        srcs: java files to be linted
        rulesets: list of labels of the PMD ruleset files
        stdout: output file to generate
        exit_code: output file to write the exit code.
            If None, then fail the build when PMD exits non-zero.
        options: additional command-line options, see https://pmd.github.io/pmd/pmd_userdocs_cli_reference.html
    """
    inputs = srcs + [exclude_filter]
    outputs = [stdout]

    # Wire command-line options, see
    # https://docs.pmd-code.org/latest/pmd_userdocs_cli_reference.html
    args = ctx.actions.args()

    args.add("-textui")

    args.add_all(options)

    src_args = ctx.actions.args()
    src_args.use_param_file("%s", use_always = True)
    src_args.add_all([srcs])

    print("args", args, src_args)

    if exit_code:
        command = "{SPOTBUGS} $@ >{stdout}; echo $? > " + exit_code.path
        outputs.append(exit_code)
    else:
        # Create empty stdout file on success, as Bazel expects one
        command = "{SPOTBUGS} $@ && touch {stdout}"

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        command = command.format(SPOTBUGS = executable.path, stdout = stdout.path),
        arguments = [args, src_args],
        mnemonic = _MNEMONIC,
        tools = [executable],
        progress_message = "Linting %{label} with Spotbugs",
    )

# buildifier: disable=function-docstring
def _spotbugs_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []

    files_to_lint = target[JavaInfo].runtime_output_jars
    outputs, info = output_files(_MNEMONIC, target, ctx)
    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    # https://github.com/pmd/pmd/blob/master/docs/pages/pmd/userdocs/pmd_report_formats.md
    # format_options = ["--format", "textcolor" if ctx.attr._options[LintOptionsInfo].color else "text"]
    format_options = []
    spotbugs_action(ctx, ctx.executable._spotbugs, files_to_lint, ctx.file._exclude_filter, outputs.human.out, outputs.human.exit_code, format_options)
    spotbugs_action(ctx, ctx.executable._spotbugs, files_to_lint, ctx.file._exclude_filter, outputs.machine.out, outputs.machine.exit_code)
    return [info]

def lint_spotbugs_aspect(binary, exclude_filter, rule_kinds = ["java_binary", "java_library"]):
    """A factory function to create a linter aspect.

    Attrs:
        binary: a PMD executable. Can be obtained from rules_java like so:

            ```
            java_binary(
                name = "pmd",
                main_class = "net.sourceforge.pmd.PMD",
                # Point to wherever you have the java_import rule defined, see our example
                runtime_deps = ["@net_sourceforge_pmd"],
            )
            ```

        rulesets: the PMD ruleset XML files
    """
    return aspect(
        implementation = _spotbugs_aspect_impl,
        # Edges we need to walk up the graph from the selected targets.
        # Needed for linters that need semantic information like transitive type declarations.
        attr_aspects = ["deps"],
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_spotbugs": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
            ),
            "_exclude_filter": attr.label(
                doc = "Report all bug instances except those matching the filter specified by this filter file",
                allow_single_file = True,
                default = exclude_filter,
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
        },
    )

def fetch_spotbugs():
    """A repository macro used from WORKSPACE to fetch ruff binaries.

    Allows the user to select a particular ruff version, rather than get whatever is pinned in the `multitool.lock.json` file.

    Args:
        tag: a tag of ruff that we have mirrored, e.g. `v0.1.0`
    """
    pass

#    maven_install(
#        name = "maven_spotbugs",
#        artifacts = [
#            "com.github.spotbugs:spotbugs:4.8.6",
#        ],
#        fail_if_repin_required = True,
#        fetch_sources = True,
#        maven_instal_json = "//:rules_jvm_external~~maven~maven_spotbugs_install.json",
#        strict_visibility = True,
#    )
