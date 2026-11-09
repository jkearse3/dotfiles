# The macOS `Herdr.app` bundle (`herdrAppBundle`) and the fixture-checked
# script the activation installs it with (`checkedInstallBundle`).
{
  herdrApp,
  lib,
  pkgs,
  profileDirectory,
}:
let
  # The package ships only `bin/herdr-app`, which Spotlight and the Dock
  # cannot launch. This bundle follows upstream `scripts/install-macos`. Its
  # executable is the real app binary, not the package's PATH wrapper, so the
  # process belongs to the bundle and shows its name and icon in the Dock.
  # Running from `Herdr.app/Contents/MacOS/Herdr`, the app links
  # `~/.local/bin/herdr-app` to itself (herdr-app `src/core_bin/cli_link.rs`);
  # the profile's `herdr-app` stays ahead of it on PATH.
  herdrAppInfoPlist = pkgs.writeText "Info.plist" (
    lib.generators.toPlist { escape = true; } {
      CFBundleExecutable = "Herdr";
      CFBundleIdentifier = "dev.herdr.app";
      CFBundleName = "Herdr";
      CFBundleDisplayName = "Herdr";
      CFBundleIconFile = "Herdr";
      CFBundlePackageType = "APPL";
      CFBundleShortVersionString = herdrApp.version;
      CFBundleVersion = herdrApp.version;
      NSPrincipalClass = "NSApplication";
      NSHighResolutionCapable = true;
      # Finder and Dock launches do not get the login shell's PATH. The app
      # looks for `hc` on PATH, and the profile's comes first so that it
      # finds the wrapped one, which drops the TUI's pane variables. On those
      # launches the app also puts the login shell's PATH in front
      # (herdr-app `src/core_bin.rs` `fill_path`).
      LSEnvironment.PATH = lib.concatStringsSep ":" [
        "${profileDirectory}/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ];
    }
  );
  herdrAppBundle = pkgs.runCommandLocal "herdr-app-bundle" { } ''
    contents=$out/Applications/Herdr.app/Contents
    mkdir -p $contents/MacOS $contents/Resources
    cp ${herdrAppInfoPlist} $contents/Info.plist
    cp ${herdrApp}/bin/.herdr-app-wrapped $contents/MacOS/Herdr
    cp ${herdrApp.src}/assets/icons/Herdr.icns $contents/Resources/Herdr.icns
  '';

  installBundle = pkgs.writeShellApplication {
    name = "herdr-app-install-bundle";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./install-bundle.sh;
  };

  # The activation runs the script through this path, so failing fixtures
  # fail the build.
  checkedInstallBundle = pkgs.runCommandLocal "herdr-app-install-bundle-checked" { } ''
    bash ${./install-bundle-test.sh} ${installBundle}/bin/herdr-app-install-bundle
    ln -s ${installBundle} "$out"
  '';
in
{
  inherit herdrAppBundle checkedInstallBundle;
}
