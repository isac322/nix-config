# Vercel's CLI, which nixpkgs does not carry under any name. `vercel` and
# `vercel-cli` do not exist there; the only near miss is `vercel-pkg`, which is
# the renamed zeit/pkg bundler and unrelated.
#
# The source is the published npm tarball rather than a GitHub checkout, for
# the same reason as langfuse-cli: the repository is a monorepo whose CLI
# package builds its bundle in a prepublish step, and `files` in package.json
# is `["dist"]` — the tarball is that bundle, and the version number names it.
{
  lib,
  buildNpmPackage,
  fetchurl,
}:

buildNpmPackage (finalAttrs: {
  pname = "vercel-cli";
  version = "58.9.4";

  src = fetchurl {
    url = "https://registry.npmjs.org/vercel/-/vercel-${finalAttrs.version}.tgz";
    hash = "sha256-0qg5khW/aivbZmlcfp74fvZD2Gy/yynBaktbpIbSg+Q=";
  };

  # Both files next to this one are the published ones, edited, and the two go
  # together: `npm ci` refuses to run unless the manifest and the lock agree.
  #
  # The lock has to be vendored because npm tarballs never carry one, and `npm
  # ci` — the reason buildNpmPackage is reproducible at all — is what needs it.
  # Generating it meant editing the manifest first, twice over.
  #
  # devDependencies goes because it cannot be resolved at all: three of its
  # entries — @vercel-internals/constants, /get-package-json and /types — are
  # workspace packages that were never published, so `npm install
  # --package-lock-only` stops on a 404 from the registry. `--omit=dev` does
  # not help, because the lock file describes the whole ideal tree regardless
  # of what would be installed from it. None of it is needed: dist/ is already
  # built and nothing here compiles or tests.
  #
  # optionalDependencies goes to save about 270 MB. It is four builds of the
  # same thing — @vercel/vc-native-{darwin,linux}-{arm64,x64}, ~68 MB each —
  # and prefetch-npm-deps fetches every entry in the lock, this platform's or
  # not. dist/vc.js prefers one of them over the JS CLI only when the user has
  # opted in through `useNativeBinary`, so without them the shim finds nothing
  # and runs the JS path, which is the default and the complete one.
  #
  # To move the version above:
  #
  #   curl -O https://registry.npmjs.org/vercel/-/vercel-<version>.tgz
  #   tar xf vercel-<version>.tgz && cd package
  #   jq 'del(.devDependencies) | del(.optionalDependencies)' package.json > p
  #   mv p package.json
  #   npm install --package-lock-only --ignore-scripts
  #   nix run nixpkgs#prefetch-npm-deps -- package-lock.json   # npmDepsHash
  #
  # then copy package.json and package-lock.json here.
  #
  # The edited manifest is copied in rather than produced by a jq call in this
  # phase, because postPatch runs twice: buildNpmPackage builds the dependency
  # cache in a second, fixed-output derivation that shares src and postPatch
  # with this one and receives none of its build inputs, so anything reaching
  # for a tool there dies with "command not found". A later phase is no escape
  # either — npmConfigHook appends itself to postPatchHooks, so the `npm ci`
  # that compares the two files has already run by the time preConfigure would.
  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-RN/3cTvlfI67hK7u7fl4XbLaFovJrvjVv1Y+OiAhwVE=";

  # dist/ ships built, and `build` is the monorepo script that produced it —
  # it wants a checkout this tarball is not.
  dontNpmBuild = true;

  # `--version` is answered by dist/vc.js before it loads anything, and would
  # pass with node_modules missing entirely — which, given that the whole point
  # of the manifest surgery above is to decide what ends up in node_modules, is
  # the failure this needs to catch. `telemetry status` is the cheapest command
  # that goes through the real command dispatch and the global config store,
  # and it wants neither credentials nor a network the sandbox does not have.
  #
  # VERCEL_TELEMETRY_DISABLED because otherwise a build would report itself to
  # Vercel — or rather try to, from a sandbox with no route out. It applies to
  # the run and not to the stored preference, so it does not decide anything on
  # the user's behalf; `vercel telemetry disable` is theirs to run.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export VERCEL_TELEMETRY_DISABLED=1
    $out/bin/vercel --version | grep -qF "${finalAttrs.version}"
    $out/bin/vercel telemetry status > /dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line interface for Vercel";
    homepage = "https://vercel.com/docs/cli";
    license = lib.licenses.asl20;
    mainProgram = "vercel";
    platforms = lib.platforms.unix;
    maintainers = [ ];
  };
})
