/*
 * The purpose of the code in this file is to provide a deterministic build
 * environment for building Postgres, using different versions of the packages
 * needed to build Postgres.
 */
let
  config = rec {
    # The root where all farm animals' files will be stored.
    #
    # The following commands are necessary to allow the nixbld
    # user, the OS user that the nix-daemon runs as in a
    # multi-user installation, to write output to the farm_root
    # directory.
    #
    #   sudo chgrp -R nixbld $FARM_ROOT
    #   chmod -R g+w $FARM_ROOT
    #
    FARM_ROOT = "/Users/gurjeet/dev/HaathiFarm/farm_root";
    PG_MIRROR = "${FARM_ROOT}/POSTGRES";
  };
  currentSystem = builtins.currentSystem;
  derivation    = builtins.derivation   ;
  fetchGit      = builtins.fetchGit     ;
  isPath        = builtins.isPath       ;
  nixVersion    = builtins.nixVersion   ;
  langVersion   = builtins.langVersion  ;
  readFile      = builtins.readFile     ;
  substring     = builtins.substring    ;
  toFile        = builtins.toFile       ;
  toString      = builtins.toString     ;

  # Use a specific version of Nixpkgs.
  nixpkgs_set = fetchGit {
    url = "git@github.com:NixOS/nixpkgs.git";
    ref = "release-22.05";
    rev = "52527082ea267fe486f0648582d57c85486b2031";
  };

  # Evaluate the code in Nixpkgs.
  nixpkgs_function = import nixpkgs_set;

  # Execute the function to get all the package definitions.
  nixpkgs_derivations = nixpkgs_function {};

  stdenv_pkg = nixpkgs_derivations.stdenv;

  # Is the current platform a Darwin derivative?
  is_darwin = stdenv_pkg.hostPlatform.isDarwin;

  # Binaries
  bash_path     = toString nixpkgs_derivations.bash;
  binutils_path = toString (if is_darwin then
                              nixpkgs_derivations.darwin.cctools
                            else
                              nixpkgs_derivations.binutils);

      bison_path = toString nixpkgs_derivations.bison;
  coreutils_path = toString nixpkgs_derivations.coreutils;
  diffutils_path = toString nixpkgs_derivations.diffutils;
       flex_path = toString nixpkgs_derivations.flex;
       gawk_path = toString nixpkgs_derivations.gawk;
        gcc_path = toString nixpkgs_derivations.gcc;
    gnugrep_path = toString nixpkgs_derivations.gnugrep;
    gnumake_path = toString nixpkgs_derivations.gnumake;
     gnused_path = toString nixpkgs_derivations.gnused;
       perl_path = toString nixpkgs_derivations.perl;

  # Libraries
  readline_out_path = toString nixpkgs_derivations.readline.out;
  readline_dev_path = toString nixpkgs_derivations.readline.dev;
      zlib_out_path = toString nixpkgs_derivations.zlib.out;
      zlib_dev_path = toString nixpkgs_derivations.zlib.dev;

  # Dev dependencies; for when using interactively, say, in nix-shell
  which_path = toString nixpkgs_derivations.which;
  less_path  = toString nixpkgs_derivations.less;

  pgbuildfarm_src = fetchGit {
    url = "git@github.com:PGBuildFarm/client-code.git";
    ref = "main";
    rev = "7df1a93251899a8ef33ef72d0bb72eb5607297fa";
  };

  # Save our Nix code, this very file, to the Nix Store; for aid in
  # troubleshooting.
  source_nix = readFile ./default.nix; 
  source_nix_in_store = toFile "default.nix" source_nix;

  # Save the driver script in Nix store; for aid in troubleshooting.
  builder_sh = readFile ./builder.sh;
  builder_sh_in_store = toFile "builder.sh" builder_sh;

  # Check that x is an absolute path.
  #
  # Convert the config to path type; this will fail if path does not exist, or
  # if the path contains illegal characters (per Nix), like a space. Then make
  # sure that the path starts with a `/`.
  is_absolute_path = x:
    isPath (/. + x) && (substring 0 1 x) == "/";

in

  assert is_absolute_path config.FARM_ROOT;
  assert is_absolute_path config.PG_MIRROR;

  derivation {

    # Binaries/executables
    inherit
      bash_path
      binutils_path
      bison_path
      coreutils_path
      diffutils_path
      flex_path
      gawk_path
      gnugrep_path
      gnumake_path
      gnused_path
      gcc_path
      perl_path;

    # Libraries
    inherit
      readline_out_path
      readline_dev_path
      zlib_out_path
      zlib_dev_path;

    # Dev dependencies
    inherit
      less_path
      which_path;

    inherit
      currentSystem
      nixVersion
      langVersion
      source_nix_in_store;

    FARM_ROOT = config.FARM_ROOT;
    PG_MIRROR = config.PG_MIRROR;

    inherit pgbuildfarm_src;

    name   = "haathi";      # Our animals' root name.
    system = currentSystem; # Let's try to support all the
                            # systems that Nix supports.
    builder = "${bash_path}/bin/bash";

    args = [ builder_sh_in_store ];
  }

