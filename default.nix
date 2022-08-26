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

  # Is the platform target a Darwin derivative
  is_darwin = stdenv_pkg.hostPlatform.isDarwin;

  # Binaries
  bash_path      = toString nixpkgs_derivations.bash;
  binutils_path  = toString (if is_darwin then
                              nixpkgs_derivations.darwin.cctools
                            else
                              nixpkgs_derivations.binutils);
  bison_path     = toString nixpkgs_derivations.bison;
  coreutils_path = toString nixpkgs_derivations.coreutils;
  diffutils_path = toString nixpkgs_derivations.diffutils;
  flex_path      = toString nixpkgs_derivations.flex;
  gawk_path      = toString nixpkgs_derivations.gawk;
  gcc_path       = toString nixpkgs_derivations.gcc;
  gnugrep_path   = toString nixpkgs_derivations.gnugrep;
  gnumake_path   = toString nixpkgs_derivations.gnumake;
  gnused_path    = toString nixpkgs_derivations.gnused;
  perl_path      = toString nixpkgs_derivations.perl;

  # Libraries
  readline_out_path = toString nixpkgs_derivations.readline.out;
  readline_dev_path = toString nixpkgs_derivations.readline.dev;
  zlib_out_path     = toString nixpkgs_derivations.zlib.out;
  zlib_dev_path     = toString nixpkgs_derivations.zlib.dev;

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

  # The driver script
  builder = toFile "builder.sh" ''
    #!/usr/bin/env bash

    # Exit shell on error
    set -e

    # Read the optional environment variables, before we prohibit access of
    # undefined variables.
    #
    # If we intend to inherit any of the environment variables, this is the
    # place to inherit them with a new name. Using a name different than the
    # original is desirable, since we want to catch any of the packages that
    # may depend on the values of such variables.
    #
    # For example:
    # in_nix_shell=$IN_NIX_SHELL

    # Throw error on undefined variables
    set -u

    _log_file="$out/builder.log"
    function log_file() { echo "$_log_file";}
    function _log()
    {
       local log_type="$1";
       shift;
       echo "$(date) $log_type: $@" | tee -a "$_log_file";
    }

    function info() { _log INFO  "$@";             }
    function warn() { _log WARN  "$@" >&2;         } # Emit message to stderr
    function error(){ _log ERROR "$@" >&2; exit 1; } # ditto, then exit.

    #### Emit enough info for later troubleshooting ####

    # Change PATH enough to use `mkdir`, and a few other commands, necessary for
    # logging.
    #
    # Note that we _don't_ use the $PATH passed to us in the environment.
    export PATH="$coreutils_path/bin"
    mkdir "$out"

    info "uname -a: $(uname -a)"
    info Nix builtins.currentSystem: ${currentSystem}
    info Nix CLI version is ${nixVersion}.
    info Nix language version is ${toString langVersion}.
    info Source Nix file is at ${source_nix_in_store}.
    info "OS {user; groups}: {$(whoami); $(groups)}"
    info "Exported and unexported shell variables: $(printf '\n'; declare -p)"

    # Record the checksum of impure files that may be used by Postgres
    info Checksums of some of the files from outside Nix Store:
    info $(sha256sum /bin/sh) # Used by many scripts, and pg_ctl, in particular.

    rc=0
    touch "$FARM_ROOT/touched_from_Nix_builder.txt" || rc=$?
    if [[ $rc -ne 0 ]]; then
      error "Could not touch file in Farm Root."\
        "You might need to change the Farm Root be of group 'nixbld', and its permissions to be group-writable."
    fi

    #### Prepare to build Postgres ####

    # Place binaries in $PATH.
    #
    # Note that we _don't_ use the $PATH passed to us in the environment.
    export PATH="$bash_path/bin:$binutils_path/bin:$bison_path/bin:$coreutils_path/bin:$diffutils_path/bin:$flex_path/bin/:$gawk_path/bin:$gcc_path/bin:$gnugrep_path/bin:$gnumake_path/bin:$gnused_path/bin:$perl_path/bin"

    # Dev dependencies; necessary only when, say, in interactive nix-shell
    # environment.
    export PATH="$PATH:$less_path/bin:$which_path/bin"

    # Set flags to help find libraries and their header files.
    #
    # Note that we _don't_ use the corresponding values, if any, passed to us
    # in the environment.
    export LDFLAGS=" -L$readline_out_path/lib     -L$zlib_out_path/lib"
    export CFLAGS="  -I$readline_dev_path/include -I$zlib_dev_path/include"
    export CPPFLAGS="-I$readline_dev_path/include -I$zlib_dev_path/include"

    cd "$PG_MIRROR"

    ./configure --config-cache --prefix=$(pwd)/db/
    make install
    make check
  '';

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

    FARM_ROOT = config.FARM_ROOT;
    PG_MIRROR = config.PG_MIRROR;

    inherit pgbuildfarm_src;

    name   = "haathi";      # Our animals' root name.
    system = currentSystem; # Let's try to support all the
                            # systems that Nix supports.
    builder = "${bash_path}/bin/bash";

    args = [ builder ];
  }

