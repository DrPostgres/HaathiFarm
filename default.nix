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

  # Binaries
  bash_path      = toString nixpkgs_derivations.bash;
  binutils_path  = toString nixpkgs_derivations.binutils;
  bison_path     = toString nixpkgs_derivations.bison;
  coreutils_path = toString nixpkgs_derivations.coreutils;
  flex_path      = toString nixpkgs_derivations.flex;
  gawk_path      = toString nixpkgs_derivations.gawk;
  gnugrep_path   = toString nixpkgs_derivations.gnugrep;
  gnumake_path   = toString nixpkgs_derivations.gnumake;
  gnused_path    = toString nixpkgs_derivations.gnused;
  gcc_path       = toString nixpkgs_derivations.gcc;
  perl_path      = toString nixpkgs_derivations.perl;



  # Libraries
  readline_out_path = toString nixpkgs_derivations.readline.out;
  readline_dev_path = toString nixpkgs_derivations.readline.dev;
  zlib_out_path     = toString nixpkgs_derivations.zlib.out;
  zlib_dev_path     = toString nixpkgs_derivations.zlib.dev;

  # Dev dependencies; for when using nix-shell
  which_path     = toString nixpkgs_derivations.which;
  less_path     = toString nixpkgs_derivations.less;

  pgbuildfarm_src = fetchGit {
    url = "git@github.com:PGBuildFarm/client-code.git";
    ref = "main";
    rev = "7df1a93251899a8ef33ef72d0bb72eb5607297fa";
  };

  # Save our Nix code, this very file, to the Nix Store; for aid in
  # troubleshooting.
  source_nix = readFile ./default.nix; 
  source_nix_in_store = toFile "default.nix" source_nix;

  builder = toFile "builder.sh" ''
    #!/usr/bin/env bash

    set -eu

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

    # Change PATH enough to use `mkdir`. This is necessary to
    # let us capture logging info in a file inside $out.
    export PATH="$coreutils_path/bin/:$PATH"
    mkdir "$out"

    info "uname -a: $(uname -a)"
    info Nix builtins.currentSystem: ${currentSystem}
    info Nix CLI version is ${nixVersion}.
    info Nix language version is ${toString langVersion}.
    info Source Nix file is at ${source_nix_in_store}.
    info "OS {user; groups}: {$(whoami); $(groups)}"
    info Exported and unexported shell variables:
    declare -p >> "$(log_file)"

    rc=0
    touch "$FARM_ROOT/touched_from_Nix_builder.txt" || rc=$?
    if [[ $rc -ne 0 ]]; then
      error "Could not touch file in Farm Root."\
        "You might need to change the Farm Root be of group 'nixbld', and its permissions to be group-writable."
    fi

    #### Prepare to build Postgres ####

    f="$binutils_path/nix-support/orig-bintools"
    binutils_orig=
    if [[ -f "$f" ]]; then
      binutils_orig=$(cat "$f")
    fi
    info "binutils_orig: $binutils_orig"

    ${if stdenv_pkg.hostPlatform.isDarwin then "export AR=/usr/bin/ar" else ""}


    export PATH="$bash_path/bin:$binutils_path/bin:$bison_path/bin:$coreutils_path/bin:$flex_path/bin/:$gawk_path/bin:$gnused_path/bin:$gnugrep_path/bin:$gnumake_path/bin:$gcc_path/bin:$perl_path/bin:$PATH"

    # Dev dependencies
    export PATH="$PATH:$less_path/bin:$which_path/bin"

    # Libraries
    export LDFLAGS="-L$readline_out_path/lib -L$zlib_out_path/lib" # Don't inherit $LDFLAGS
    export CFLAGS="-I$readline_dev_path/include -I$zlib_dev_path/include" # Don't inherit $CFLAGS
    export CPPFLAGS="-I$readline_dev_path/include -I$zlib_dev_path/include" # Don't inherit $CPPFLAGS

    export SHELL # So that pg_regress' Makefile can embed this into the pg_regress binary.

    sh -c 'echo Hello there'

    info cd pg sources
    cd "$PG_MIRROR"
    info dist-cleaning
    make distclean || true
    info configuring
    ./configure --prefix=$(pwd)/db/ SHELL="$(which sh)"
    info making
    make -j 8 install
    make install
    make check
  '';

in

  # Ensure that the FARM_ROOT exists, and that it's an absolute path.
  #
  # Convert the config to # Path type; this will fail if path does not exist,
  # or if the path contains illegal (in Nix) characters, like a space. And make
  # sure that the Farm Root path starts with a `/`;
  assert isPath (/. + config.FARM_ROOT);
  assert (substring 0 1 config.FARM_ROOT) == "/";

  derivation {
    inherit bash_path bison_path coreutils_path flex_path gawk_path gnugrep_path gnumake_path gnused_path gcc_path perl_path;

    inherit readline_out_path readline_dev_path zlib_out_path zlib_dev_path;

    # Dev dependencies
    inherit less_path which_path;

    #inherit bintools_path;
    inherit binutils_path;

    FARM_ROOT = config.FARM_ROOT;
    PG_MIRROR = config.PG_MIRROR;

    inherit pgbuildfarm_src;

    name   = "haathi";      # Our animals' root name.
    system = currentSystem; # Let's try to support all the
                            # systems that Nix supports.
    builder = "${bash_path}/bin/bash";

    args = [ builder ];
  }

