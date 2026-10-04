{ inputs, ... }:
{
  imports = [ inputs.cod-clients.homeModules.default ];

  # cod-plutonium: Plutonium launcher (BO2 / T6, also BO1, WaW, MW3).
  # Fetches the official self-updating client at runtime, builds a Proton
  # prefix with the winetricks verbs it needs, and runs under umu-launcher
  # inside a bubblewrap sandbox.
  #
  # The sandbox only exposes Steam library paths, so a hand-dropped T6 build in
  # ~/Games stays hidden. We let the launcher keep its own managed copy
  # instead, which also sidesteps the incomplete download in
  # ~/Games/pluto_t6_full_game (it has zone/sound/video but no _out or
  # t6mp.exe, so it cannot run).
  #
  # dotnet stays off: it is only needed for MW3/IW5, and BO1/BO2/WaW do not
  # use it. It is a slow install.
  #
  # Override Proton for one launch without rebuilding:
  #   COD_PROTON=/path/to/proton cod-plutonium
  # Or bypass the sandbox for one launch:
  #   COD_SANDBOX=0 cod-plutonium
  myModules.home.cod-clients = {
    enable = true;
    sandbox = true;

    plutonium = {
      enable = true;
      dotnet = false;
    };
  };
}
