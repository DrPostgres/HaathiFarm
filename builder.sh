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
   echo "$(date --iso-8601=seconds) $log_type: $@" | tee -a "$_log_file";
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
info Nix language version is ${langVersion}.
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
    "You might need to change the Farm Root directory to be in the group 'nixbld', and the directory's permissions to be group-writable."
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
