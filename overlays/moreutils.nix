_final: prev: {
  # moreutils ships its own `parallel`, whose syntax differs from GNU parallel's.
  # Agents and humans expect GNU syntax from that name, so this variant drops it
  # and keeps the other tools. A separate attribute leaves `moreutils` itself,
  # and every package that depends on it, unchanged.
  moreutils-without-parallel = prev.moreutils.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      rm "$out/bin/parallel" "$out/share/man/man1/parallel.1"
    '';
  });
}
