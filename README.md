# Overview
 This tool runs Renovate in a containerized, self-hosted environment.

 Admittedly, it's handy to use the Mend Renovate app on the repository
 host and call it done.  True.  However, if for whatever reason
 (e.g., organizational policy, a repository host that doesn't
 support running apps, etc.), an alternative solution may be to run
 Renovate locally (i.e., self-host), particularly if Renovate can
 be run in a containerized environment (e.g., with Docker).

 It may also be convenient to be able to run Renovate with different
 configurations, with different endpoints, different tokens, different
 accounts, etc..

 That's where this script comes in -- it allows the user to specify
 a configuration file and a .env-formatted file (the filename doesn't
 matter; in fact, the default filename is 'renovate.env') and let it
 run.  One may even use this in conjunction with `find` to automate
 even further.

 When renovator runs, it is passed a configuration file (Renovate
 supports JavaScript (.js) or JSON files) and an env file.  This
 was done to allow the same credentials to be used in multiple
 configurations and to allow for the safe storage of the config
 files without including secrets (credentials, tokens, etc.) in
 a public repository.  Please don't store secrets with the source
 code in a repository.

 When run, if a requested config or env file is missing, it will
 be automatically created from a template.  The created file will
 be basic, minimal example that can be updated with appropriate
 values as-needed.  The env file has several commented lines
 while the config file specifies GitHub along with a few common
 variables set to default, demonstrative values.  That is, using
 a default env or config file along with an appropriately-populated
 file (i.e., a populated config file and an empty env file) shouldn't
 cause any problems.

 Why are the sample configuration files stored as Bash heredocs?
 So that a single Bash file can be pulled from the repo and run
 directly (e.g., curl "https://.../renovator.bash" | bash -)

 The script also allows for alternative container engines
 (e.g., Docker, podman, etc.)

## Usage

| Long         | Short | Meaning                             |
| ------------ | ----- | ----------------------------------- |
| --configfile | -c    | set the configuration file filename |
| --engine		 | -E    | set the container engine            |
| --envfile		 | -e    | set the .env file filename          |
| --help		   | -h    | view the help documentation         |
| --image      | -i    | set the container image to use      |

## Examples

```bash
# run using a specific configuration and environment
./renovator.bash -c /path/to/myreops.json -e /path/to/myrepos.env

# iterate through subdirectories of configs assuming default filenames
find configs \
  -mindepth 1 \
  -type d \
  -exec ./renovator.bash -e "{}/renovate.env" -c "{}/renovate.json" \;
```


