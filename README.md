# angie-ctl

A simple script for managing Angie HTTP configurations and modules, similar to a2enconf/a2enmod for Apache.
It allows you to enable, disable, and list available/enabled configs and modules via symlinks.

## Features

- Enable/disable HTTP configs and modules by name
- List available and enabled configs/modules
- Automatically validate Angie configuration after changes

## Usage

```
./angie-ctl.sh {httpconf|mod} {en|dis|ls|ls-available|ls-enabled} [name ...]
```

### Examples

Enable a config:

```
./angie-ctl.sh httpconf en drupal
./angie-ctl.sh httpconf en drupal.conf
```

Disable a config:

```
./angie-ctl.sh httpconf dis drupal
```

Enable a module:

```
./angie-ctl.sh mod en geoip
```

Disable a module:

```
./angie-ctl.sh mod dis geoip
```

List enabled configs/modules:

```
./angie-ctl.sh httpconf ls
./angie-ctl.sh mod ls
```

List all available configs/modules:

```
./angie-ctl.sh httpconf ls-available
./angie-ctl.sh mod ls-available
```

List all enabled configs/modules:

```
./angie-ctl.sh httpconf ls-enabled
./angie-ctl.sh mod ls-enabled
```

## Directories

- Available configs: `/etc/angie/http-conf-available.d`
- Enabled configs: `/etc/angie/http-conf.d`
- Available modules: `/etc/angie/modules-available.d`
- Enabled modules: `/etc/angie/modules.d`

## Requirements

- Installed Angie, available via `$ANGIE_BIN` (default: `angie`)
- Sufficient permissions to create/remove symlinks in Angie config directories

## Notes

- After enabling/disabling, the script runs `angie -t` to validate the configuration
- Names can be specified with or without the `.conf` extension
