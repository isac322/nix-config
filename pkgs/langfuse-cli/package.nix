# Langfuse's CLI, which nixpkgs does not carry — neither as `langfuse-cli` nor
# under nodePackages. The `langfuse` attribute in nixpkgs is the Python SDK and
# has no `langfuse` binary in it.
#
# The source is the published npm tarball rather than a GitHub checkout. The
# repository has no tags at all, and `dist/` is in its .gitignore: the bundle
# is produced by `bun build` in a prepublish hook, so a checkout would mean
# adding bun to the build just to regenerate a file npm already ships. The
# tarball is that bundle, and it is what the version number refers to.
{
  lib,
  buildNpmPackage,
  fetchurl,
}:

buildNpmPackage (finalAttrs: {
  pname = "langfuse-cli";
  version = "0.0.12";

  src = fetchurl {
    url = "https://registry.npmjs.org/langfuse-cli/-/langfuse-cli-${finalAttrs.version}.tgz";
    hash = "sha256-yJjaQ3/hNGNge68fqqgnPxDVOvDos9m27q+2vceMukM=";
  };

  # npm tarballs carry no lock file, and `npm ci` — which is the whole reason
  # buildNpmPackage is reproducible — refuses to run without one. So the lock
  # is generated once by hand and kept next to this file:
  #
  #   npm install --package-lock-only --legacy-peer-deps
  #   nix run nixpkgs#prefetch-npm-deps -- package-lock.json   # npmDepsHash
  #
  # Regenerate both whenever the version above moves.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-idh7HteAQZAmPUvDFzZTM4LcGBoZt3r9tG/DztqZhuY=";

  # Both the lock file and this install have to skip peer resolution, and for a
  # reason rather than to silence an error. The one dependency, specli, declares
  # `ai` and `zod` as peers; npm would pull them in along with a dozen
  # transitive packages, undici among them. Nothing on the CLI path imports
  # either — they are used only by specli's dist/ai/tools.js, which is a
  # separate export this CLI never loads.
  npmFlags = [ "--legacy-peer-deps" ];

  # dist/cli.js is already built, and the package's only build script is the
  # bun invocation that produced it.
  dontNpmBuild = true;

  # The bundle is nearly self-contained — its one runtime import is
  # `import.meta.resolve("specli")`, resolved at the moment an api subcommand
  # runs rather than at load. So `--help` proves nothing: it prints its usage
  # perfectly well with node_modules missing entirely, which is exactly the way
  # this package would break. `api __schema` is the cheapest command that goes
  # through that import, and it reads the OpenAPI spec bundled in the tarball,
  # so it needs neither credentials nor a network the sandbox does not have.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/langfuse api __schema > /dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Command line interface for Langfuse";
    homepage = "https://github.com/langfuse/langfuse-cli";
    license = lib.licenses.mit;
    mainProgram = "langfuse";
    platforms = lib.platforms.unix;
    # Empty rather than absent: nixpkgs requires the attribute on new packages,
    # and there is no handle in the pinned tree to put in it.
    maintainers = [ ];
  };
})
