# Registers the standalone tests that `nix flake check` and `./x.sh check` run.
#
# A test runs in the derivation that delivers what it tests, or, when nothing
# builds it, as a check registered explicitly here. Repository packages run
# their tests at build time, but the home build does not necessarily build
# every package, so they are registered here too.
{
  perSystem =
    {
      config,
      ...
    }:
    {
      # treefmt-nix contributes the `treefmt` check; the module system merges it
      # with these.
      checks = config.packages // { };
    };
}
