# Configs

This directory can be used to store configuration files, .env files, or really
whatever you want it to store.  For example, if each different set of
configuration file was stored in a separate subdirectory of `configs/` and
each .env file was named `renovate.env` and each configuration file was named
`renovate.json`, then the following could be used to iterate across the lot:

```bash
find configs \
  -mindepth 1 \
  -type d \
  -exec ./renovator.bash -e "{}/renovate.env" -c "{}/renovate.json" \;
```
