{ pkgs, ... }:

{
  # Lua 5.2 — the version Factorio embeds, and the one the busted suite must
  # run on so the tests match in-game behaviour.
  languages.lua = {
    enable = true;
    package = pkgs.lua5_2;
  };

  packages = [
    pkgs.lua52Packages.busted # test runner, built against Lua 5.2
    pkgs.stylua # Lua formatter
  ];

  # `devenv test` and the `test` script both run the suite from the repo root,
  # where .busted resolves the domain/ modules.
  scripts.test.exec = "busted";

  enterShell = ''
    echo "LamentedCircuitAdditions — Lua $(lua -v 2>&1)"
    echo "run 'busted' (or 'test') for the domain suite"
  '';

  enterTest = ''
    busted
  '';
}
