{
  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    systems.url = "github:nix-systems/default";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixGL.url = "github:guibou/nixGL";
  };

  outputs = {
    self,
    systems,
    nixpkgs,
    treefmt-nix,
    nixGL,
    ...
  } @ inputs: let
    eachSystem = f:
      nixpkgs.lib.genAttrs (import systems) (
        system:
          f (import nixpkgs {
            inherit system;
            overlays = [inputs.rust-overlay.overlays.default nixGL.overlay];
          })
      );

    rustToolchain = eachSystem (pkgs: pkgs.rust-bin.stable.latest);
    treefmtEval = eachSystem (pkgs: treefmt-nix.lib.evalModule pkgs ./treefmt.nix);
  in {
    devShells = eachSystem (pkgs: {
      # Based on a discussion at https://github.com/oxalica/rust-overlay/issues/129
      default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          clang
          # Use mold when we are runnning in Linux
          (lib.optionals stdenv.isLinux mold)
        ];
        buildInputs = with pkgs; [
          rustToolchain.${pkgs.system}.default
          rust-analyzer-unwrapped
          cargo
          pkg-config
          alsa-lib
          fontconfig
          wayland
          libxkbcommon
          xorg.libXau
          xorg.libxcb
          openssl
          zstd
          vulkan-headers #maybe
          vulkan-loader
          vulkan-tools #maybe

          # further tests
          nixgl.nixVulkanMesa
        ];
        RUST_SRC_PATH = "${
          rustToolchain.${pkgs.system}.rust-src
        }/lib/rustlib/src/rust/library";
        LD_LIBRARY_PATH = "${pkgs.vulkan-loader}/lib:$LD_LIBRARY_PATH";
      };
    });

    packages = eachSystem (
      pkgs: {
        default = rustToolchain.buildRustPackage {
          pname = "Zed";
          src = ./.;

          cargoLock = {lockFile = ./Cargo.lock;};
        };
      }
    );

    formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);

    checks = eachSystem (pkgs: {
      formatting = treefmtEval.${pkgs.system}.config.build.check self;
    });
  };
}
