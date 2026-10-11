{
  description = "Yohaku — 余白を活かしたシンプルなメモ帳エディタ (Qt6 / QML)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      perSystem =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          qt = pkgs.qt6;

          # QtWayland は Linux のみ（Wayland のプラットフォームプラグイン）
          qtGuiInputs = with qt; [
            qtbase
            qtdeclarative
          ] ++ nixpkgs.lib.optionals pkgs.stdenv.isLinux [ qt.qtwayland ];

          yohaku = pkgs.stdenv.mkDerivation (finalAttrs: {
            pname = "yohaku";
            version = "0.1.1";
            src = ./.;

            nativeBuildInputs = [
              pkgs.cmake
              pkgs.ninja
              pkgs.pkg-config
              qt.wrapQtAppsHook
            ];
            buildInputs = qtGuiInputs;

            meta = {
              description = "余白を活かしたシンプルなメモ帳エディタ (Qt6/QML)";
              mainProgram = "yohaku";
              license = pkgs.lib.licenses.mit;
              platforms = pkgs.lib.platforms.unix;
            };
          });
        in
        {
          packages = {
            inherit yohaku;
            default = yohaku;
          };
          apps.default = {
            type = "app";
            program = "${yohaku}/bin/yohaku";
          };
          devShells.default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              cmake
              ninja
              pkg-config
              gcc
            ];
            buildInputs = qtGuiInputs;
            shellHook = ''
              echo "Yohaku (Qt6/QML) dev shell"
              echo "  cmake -B build -G Ninja && cmake --build build"
            '';
          };
          formatter = pkgs.nixpkgs-fmt;
        };
    in
    {
      packages = forAllSystems (system: (perSystem system).packages);
      apps = forAllSystems (system: (perSystem system).apps);
      devShells = forAllSystems (system: (perSystem system).devShells);
      formatter = forAllSystems (system: (perSystem system).formatter);
    };
}
