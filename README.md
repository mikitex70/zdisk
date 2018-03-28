[![Build Status](https://travis-ci.org/mikitex70/zdisk.svg?branch=master)](https://travis-ci.org/Simo/sboot)

# Persistent compressed ramdisk manager

The script `zdisk` creates a compressed ramdisk (using `zram`devices) which can be persisted in a `squashfs` filesystem, which can be restored on boot.

In this way we have the benefits of a ramdisk (speed, less stress for SSD drives), less memory usage (thanks to the `zram` devices) and without loosing contents on power off.

Moreover, the ramdisk can be very big: everytime the ramdisk contents are saved, they are added to the `squashfs` archive and the used ram becomes free (after a service restart).


## Requirements

This utility requires the following tools:

* Linux kernel versione 3.18 or upper; tested with kernel 4.14
* kernel modules `zram` and `overlay`
* `xfs` filesystem (can be changed with environment variables)
* `mksquashfs`: usually provided by the `squashfs-tools` package
* `zramctl`: sometimes provided by te `util.linux` package

If some tool is missing, use the package manager of your Linux distribution to install it.


## Install

To install the `zdisk` binary, download the `zdisk` script and run the following command:

```bash
    sudo ./zdisk install
```

which copies the `zdisk` binary into the `/usr/local/bin` folder.

### Install in a systemd environment

Optionally, it is possibile to automatically install a `systemd` service:

```bash
    sudo zdisk install --systemd [service_name]
```

The `service_name` parameter (the default value is `zdisk`) is optional and can be used to install a custom `zdisk` service, usefull if you want more than one disk.

The above command does the following:
* copies the `zdisk` binary in `/usr/local/bin`
* if the `service_name` parameter is specified and different from `zdisk`, a link `/usr/local/bin/service_name` pointing to the `zdisk` script will be created 
* creates the `/etc/systemd/system/service_name.service` file, to declare the systemd service
* creates the `/etc/conf.d/service_name` file, used to tune the `zdisk` options
* runs the `systemctl daemon-reload` command to inform systemd of the configuration change
* runs the `systemctl enable service_name` to enable the mount of the disk at system startup (can be disabled with `--autostart off`)


## Uninstall

To uninstall, run the command:

```bash
    sudo zdisk uninstall
```

which removes the zdisk binary from `/usr/local/bin`.
Please pay attention to use the previous command only if no other services are created (use the command in the next section).

### Uninstall from a systemd environment

To remove a `systemd` service, run the following command:

```bash
    sudo zdisk uninstall--systemd [service_name]
```

The above command does the following:
* stops the `service_name` (default is `zdisk`) service, if running
* disables the `service_name` from autostarting
* removes the `/etc/conf.d/service_name` configuration file
* removes the `/etc/systemd/system/service_name` service descriptor
* removes the file `/usr/local/bin/service_name` (the binary command)


## Usage

The usage is simple (all commands must be run as root, e.g. use `sudo`):

* `zdisk help` is your friend: use it to view a quick help on usage and available options
* `zdisk start` creates a persistent compressed ramdisk with size 25% of installe ram and mounted ad `/mnt/zdisk`
* `zdisk stop` saves the contentents of `/mnt/zdisk` into a `squashfs` filesystem stored in `/var/lib`; the stop can be slow, depending on the disk size and hardware (CPU and disks)
* `zdisk stop --quick` is similar to previous, but saves only the ram contents, not the whole contents of `/mnt/zdisk`; at next `zdisk start` the contents will be restored (squashed contents and quick saved). This is preferred if changed files from the whole contents are limited. This is the default when used as a `systemd` service.
* `zdisk save` can be used to trigger a save of the `/mnt/zdisk` contents without doing a `zdisk stop` (a kind of backup)

All commands can be run with an optional argument specifing the _disk name_; this can be usefull if you need more than one disk. For esmple:

```bash
    sudo zdisk start mydisk
    cp -a $HOME/mystuff /mnt/mydisk/
    # trigger a save into /var/lib/mydisk.sqfs
    sudo zdisk save mydisk 
    # stop and unmount the disk
    sudo zdisk stop mydisk
```


# Configuration

The behaviour of the `zdisk` script can be changed with environment variables or changing the relative `/etc/conf.d/zdisk` configuration file.

The available variable are (default values are shown):

```bash
    # Where to mount the persistent compressed ramdisk
    # ZDISK_MOUNTPOINT="/mnt/zdisk"

    # File where to backup ramdisk contents
    # SAVED_DISK="/var/lib/zdisk.sqfs"

    # on stop, save disk contents
    # SAVE_ON_STOP="true"

    # On start, restore previous saved disk contents
    # RESTORE_ON_START="true"

    # zdisk size will be max 25% of total memory; used (compressed) memory is (hopefully) less.
    # ZDISK_PCTSIZE=25

    # Alternatively, the ramdisk size can be explicetly set
    # ZDISK_SIZE="1G"

    # Ramdisk compression algorithm; can be lzo o lz4
    # ZDISK_ALGORITHM="lzo"

    # Filesystem to use for the ramdisk. Usually xfs consumes less space.
    # ZDISK_FS="xfs"
```

## Tests

In the `test` directory there is a test using the [BATS](https://github.com/bats-core/bats-core) framework and some extensions.

To run the tests you need to checkout some submodules (the test framework) with the following commands:

```bash
    git submodule init
    git submodule update
```

Next, you can run the tests to check if the script is working as expected:

```bash
    test/zdisk.bats
```
