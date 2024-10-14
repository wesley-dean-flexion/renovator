#!/usr/bin/env bash
## @file renovator.bash
## @author Wes Dean
## @brief wrapper to run containerized Renovate
## @details
## This tool runs Renovate in a containerized, self-hosted environment.
##
## Admittedly, it's handy to use the Mend Renovate app on the repository
## host and call it done.  True.  However, if for whatever reason
## (e.g., organizational policy, a repository host that doesn't
## support running apps, etc.), an alternative solution may be to run
## Renovate locally (i.e., self-host), particularly if Renovate can
## be run in a containerized environment (e.g., with Docker).
##
## It may also be convenient to be able to run Renovate with different
## configurations, with different endpoints, different tokens, different
## accounts, etc..
##
## That's where this script comes in -- it allows the user to specify
## a configuration file and a .env-formatted file (the filename doesn't
## matter; in fact, the default filename is 'renovate.env') and let it
## run.  One may even use this in conjunction with `find` to automate
## even further.
##
## When renovator runs, it is passed a configuration file (Renovate
## supports JavaScript (.js) or JSON files) and an env file.  This
## was done to allow the same credentials to be used in multiple
## configurations and to allow for the safe storage of the config
## files without including secrets (credentials, tokens, etc.) in
## a public repository.  Please don't store secrets with the source
## code in a repository.
##
## When run, if a requested config or env file is missing, it will
## be automatically created from a template.  The created file will
## be basic, minimal example that can be updated with appropriate
## values as-needed.  The env file has several commented lines
## while the config file specifies GitHub along with a few common
## variables set to default, demonstrative values.  That is, using
## a default env or config file along with an appropriately-populated
## file (i.e., a populated config file and an empty env file) shouldn't
## cause any problems.
##
## Why are the sample configuration files stored as Bash heredocs?
## So that a single Bash file can be pulled from the repo and run
## directly (e.g., curl "https://.../renovator.bash" | bash -)
##
## The script also allows for alternative container engines
## (e.g., Docker, podman, etc.)
##
## @par Examples
## @code
## # run using a specific configuration and environment
## ./renovator.bash -c /path/to/myreops.json -e /path/to/myrepos.env
##
## # iterate through subdirectories of configs assuming default filenames
## find configs \
##   -mindepth 1 \
##   -type d \
##   -exec ./renovator.bash -e "{}/renovate.env" -c "{}/renovate.json" \;
## @endcode

set -euo pipefail

DEFAULT_CONFIGFILE="renovate.json"
DEFAULT_ENVFILE="renovate.env"
DEFAULT_IMAGE="docker.io/renovate/renovate:full"
DEFAULT_CONTAINER_ENGINE="docker"


## @fn die
## @brief receive a trapped error and display helpful debugging details
## @details
## When called -- presumably by a trap -- die() will provide details
## about what happened, including the filename, the line in the source
## where it happened, and a stack dump showing how we got there.  It
## will then exit with a result code of 1 (failure)
## @retval 1 always returns failure
## @par Example
## @code
## trap die ERR
## @endcode
die() {
  printf "ERROR %s in %s AT LINE %s\n" "$?" "${BASH_SOURCE[0]}" "${BASH_LINENO[0]}" 1>&2

  local i=0
  local FRAMES=${#BASH_LINENO[@]}

  # FRAMES-2 skips main, the last one in arrays
  for ((i = FRAMES - 2; i >= 0; i--)); do
    printf "  File \"%s\", line %s, in %s\n" "${BASH_SOURCE[i + 1]}" "${BASH_LINENO[i]}" "${FUNCNAME[i + 1]}"
    # Grab the source code of the line
    sed -n "${BASH_LINENO[i]}{s/^/    /;p}" "${BASH_SOURCE[i + 1]}"
  done
  exit 1
}

## @fn display_usage
## @brief display some auto-generated usage information
## @details
## This will take two passes over the script -- one to generate
## an overview based on everything between the @file tag and the
## first blank line and another to scan through getopts options
## to extract some hints about how to use the tool.
## @retval 0 if the extraction was successful
## @retval 1 if there was a problem running the extraction
## @par Example
## @code
## for arg in "$@" ; do
##   shift
##   case "$arg" in
##     '--word') set -- "$@" "-w" ;;   ##- see -w
##     '--help') set -- "$@" "-h" ;;   ##- see -h
##     *)        set -- "$@" "$arg" ;;
##   esac
## done
##
## # process short options
## OPTIND=1
###
##
## while getopts "w:h" option ; do
##   case "$option" in
##     w ) word="$OPTARG" ;; ##- set the word value
##     h ) display_usage ; exit 0 ;;
##     * ) printf "Invalid option '%s'" "$option" 2>&1 ; display_usage 1>&2 ; exit 1 ;;
##   esac
## done
## @endcode
display_usage() {
  local overview
  overview="$(sed -Ene '
  /^[[:space:]]*##[[:space:]]*@file/,${/^[[:space:]]*$/q}
  s/[[:space:]]*@(author|copyright|version|)/\1:/
  s/[[:space:]]*@(note|remarks?|since|test|todo||version|warning)/\1:\n/
  s/[[:space:]]*@(pre|post)/\1 condition:\n/
  s/^[[:space:]]*##([[:space:]]*@[^[[:space:]]*[[:space:]]*)*//p' < "$0")"

  local usage
  usage="$(
    (
      sed -Ene "s/^[[:space:]]*(['\"])([[:alnum:]]*)\1[[:space:]]*\).*##-[[:space:]]*(.*)/\-\2\t\t: \3/p" < "$0"
      sed -Ene "s/^[[:space:]]*(['\"])([-[:alnum:]]*)*\1[[:space:]]*\)[[:space:]]*set[[:space:]]*--[[:space:]]*(['\"])[@$]*\3[[:space:]]*(['\"])(-[[:alnum:]])\4.*##-[[:space:]]*(.*)/\2\t\t: \6/p" < "$0"
    ) | sort --ignore-case
  )"

  if [ -n "$overview" ]; then
    printf "Overview\n%s\n" "$overview"
  fi

  if [ -n "$usage" ]; then
    printf "\nUsage:\n%s\n" "$usage"
  fi
}


## @fn get_config_file()
## @brief returns the path to the config file via STDOUT
## @details
## If a filename to a config file is passed that doesn't exist, it will
## be created with a few common defaults that one would typically
## include in a config file.  Similarly, if the directory structure
## to house the config file doesn't exist, it will be created.
##
## Renovate supports configuration files in .js or JSON format.  When
## the run_renovate() wrapper is run, it will indicate to renovate
## which type (JavaScript or JSON) the configuration file based on
## the extension of the passed-in config file.  That is, if the
## configuration file is a .js file, renovate will be told that the
## incoming file is a .js file (environment variable, bind-mount).
##
## Config files ae intended to be different from .env files in that
## .env files are intended to not be stored in a repo while config
## files may include less-sensitive information.  If you're reading this,
## it's your call.
##
## Variables passed via the environment (i.e., those in .env files)
## take precedence over those in configuration files.  As a result,
## the defaults included here ought not conflict with those passed
## by the environment.  So, a generated config file won't adversely
## affect variables passed via the environment.
##
## The actual path (realpath) to the config file is returned via STDOUT.
## @param configfile the configuration ile filename
## @returns realpath to the config file, created if necessary via STDOUT
## @par Examples
## @code
## envfile="$(get_config_file "~/my_config.js")"
## envfile="$(get_config_file "../my_config.json")"
## @endcode
get_config_file() {
  configfile="${1?Error: no config file passed}"

  mkdir -p "$(dirname "$configfile")"

  if [ ! -e "${configfile}" ] ; then
    cat << END_OF_CONFIG > "${configfile}"
{
  "onboarding": true,
  "prFooter": "This PR generated by Renovate orchestrated by Renovator.",
}
END_OF_CONFIG
  fi

  realpath "${configfile}"
}


## fn get_env_file()
## @brief returns the path to the .env file via STDOUT
## @details
## If a filename to a .env file is passed that doesn't exist, it will
## be created with a few commented out lines that one would typically
## pass via the environment.  Because the lines are commented out,
## including this as an enviroment file (--env-file flag to
## docker run), a non-existing .env file won't affect what's passed
## via the config file.  If the directory stucture for the .env file
## doesn't yet exist, it will be created.
##
## Support for .env files is provided so that sensitive information
## like credentials, tokens, etc. can be stored separately from configuration
## that could be public or stored in a source code repository.
##
## The actual path (realpath) to the .env file is returned via STDOUT
## so it's less likely that relative paths and such will cause issues
## with bind-mounted volumes.
## @param envfile the .env file filename
## @returns realpath to the config file, created if necessary via STDOUT
## @par Examples
## @code
## envfile="$(get_env_file "~/my_config.env")"
## @endcode
get_env_file() {

  envfile="${1?Error: no env file passed}"

  mkdir -p "$(dirname "$envfile")"

  if [ ! -e "${envfile}" ] ; then
    cat << END_OF_ENV > "${envfile}"
# This is a sample .env file
# RENOVATE_TOKEN=value
# RENOVATE_GITHUB_COM_TOKEN=value
END_OF_ENV
  fi

  realpath "${envfile}"
}


## @fn run_renovate()
## @brief this is a wrapper that runs the container
## @details
## This is a (very) thin wrapper around 'docker' that configures
## the container.  It maps the configuration file to where
## renovate can find it, sets up the environment, etc..
## Anything passed to this function is appended to the
## renovate container run (i.e., as if they were arguments
## to renovate).
##
## The configfile, envfile, etc. are passed as environment
## variables.
## @param configfile the configuration file (environment)
## @param envfile the .env file (environment)
## @param image the renovate image to run (environment)
## @param container_engine the tool to instantiate the container (environment)
## @returns output of renovate via STDOUT, STDERR
## @par Examples
## @code
## configfile="foo.js" envfile="foo.env" run_renovate
## @endcode
run_renovate() {

  image="${image:-${DEFAULT_IMAGE}}"
  container_engine="${container_engine:-${DEFAULT_CONTAINER_ENGINE}}"
  configfile="$(get_config_file "${configfile}")"
  envfile="$(get_env_file "${envfile}")"

  configfile_extension="${configfile##*.}"

  echo "configfile_extension='$configfile_extension'"

  internal_configfile="/usr/src/app/config.${configfile_extension}"

  "${container_engine:-docker}" run \
    --rm \
    -i \
    "$([ -t 0 ] && echo "-t")" \
    -v "${configfile}:${internal_configfile}" \
    -e "RENOVATE_CONFIG_FILE=${internal_configfile}" \
    --env-file="${envfile}" \
    "${image}" \
    "$@" \
    | sed -Ee "s|${internal_configfile}|$configfile|g"
}


## @fn main()
## @brief This is the main program loop.
main() {

  trap die ERR

  # set the defaults

  configfile="${DEFAULT_CONFIGFILE}"
  envfile="${DEFAULT_ENVFILE}"
  image="${DEFAULT_IMAGE}"
  container_engine="${DEFAULT_CONTAINER_ENGINE}"

  # translate long options into short options

  for arg in "$@"; do
    shift
    case "$arg" in
      '--configfile') set -- "$@" "-c" ;; ##- see -c
      '--engine') set -- "$@" "-E" ;; ##- see -E
      '--envfile') set -- "$@" "-e" ;; ##- see -e
      '--help') set -- "$@" "-h" ;; ##- see -h
      '--image') set -- "$@" "-i" ;; ##- see -i
      *) set -- "$@" "$arg" ;;
    esac
  done

  # parse short options

  OPTIND=1
  while getopts "c:E:e:hi:" opt; do
    case "$opt" in
      'c') configfile="$OPTARG" ;; ##- set the configuration file filename
      'E') container_engine="$OPTARG" ;; ##- set the container engine
      'e') envfile="$OPTARG" ;; ##- set the env file filename
      'i') image="$OPTARG" ;; ##- set the container image to use
      'h') display_usage ; exit 0 ;; ##- view the help documentation
      *)
        printf "Invalid option '%s'" "$opt" 1>&2
        display_usage 1>&2
        exit 1
        ;;
    esac
  done

  # reset "$@" so it starts after the flags

  shift "$((OPTIND - 1))"

  # call the function that does the thing

  configfile="$configfile" \
  envfile="$envfile" \
  image="$image" \
  container_engine="$container_engine" \
  run_renovate "$@"
}

# if we're not being sourced and there's a function named `main`, run it
[[ "$0" == "${BASH_SOURCE[0]}" ]] && [ "$(type -t "main")" = "function" ] && main "$@"
