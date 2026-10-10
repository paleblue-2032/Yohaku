{
  description = "shiori — 栞付きのシンプルなメモ帳エディタ (Qt6 / QML)";

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

          shiori = pkgs.stdenv.mkDerivation (finalAttrs: {
            pname = "shiori";
            version = "0.1.0";
            src = ./.;

            nativeBuildInputs = [
              pkgs.cmake
              pkgs.ninja
              pkgs.pkg-config
              qt.wrapQtAppsHook
            ];
            buildInputs = qtGuiInputs;

            meta = {
              description = "栞付きのシンプルなメモ帳エディタ (Qt6/QML)";
              mainProgram = "shiori";
              license = pkgs.lib.licenses.mit;
              platforms = pkgs.lib.platforms.unix;
            };
          });
        in
        {
          packages = {
            inherit shiori;
            default = shiori;
          };
          apps.default = {
            type = "app";
            program = "${shiori}/bin/shiori";
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
              echo "shiori (Qt6/QML) dev shell"
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
