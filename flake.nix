{
  description = "shiori — 栞付きのシンプルなメモ帳エディタ";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
    }:
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
          overlays = [ (import rust-overlay) ];
          pkgs = import nixpkgs { inherit system overlays; };

          rust = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          rustPlatform = pkgs.makeRustPlatform {
            cargo = rust;
            rustc = rust;
          };

          # 実行時に必要なネイティブライブラリ（Linux のみ）。
          # winit は libwayland / libxkbcommon を dlopen し、
          # wgpu は libvulkan を dlopen するため LD_LIBRARY_PATH に載せる。
          linuxLibs = with pkgs; [
            libxkbcommon
            wayland
            libGL
            vulkan-loader
            dbus
          ];
          runtimeLibs = pkgs.lib.optionals pkgs.stdenv.isLinux linuxLibs;

          shiori = rustPlatform.buildRustPackage {
            pname = "shiori";
            version = "0.1.0";
            src = ./.;
            cargoLock.lockFile = ./Cargo.lock;

            nativeBuildInputs = with pkgs; [
              pkg-config
              makeWrapper
            ];
            buildInputs = runtimeLibs;

            postFixup = pkgs.lib.optionalString pkgs.stdenv.isLinux ''
              wrapProgram $out/bin/shiori \
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath runtimeLibs}
            '';

            meta = {
              description = "栞付きのシンプルなメモ帳エディタ";
              mainProgram = "shiori";
              license = pkgs.lib.licenses.mit;
              platforms = pkgs.lib.platforms.unix;
            };
          };
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
            packages = [
              rust
              pkgs.pkg-config
              pkgs.clang
            ]
            ++ runtimeLibs;
            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath runtimeLibs;
            shellHook = ''
              echo "shiori dev shell — cargo run -- <file>"
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
