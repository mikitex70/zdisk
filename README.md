# Persistent compressed ramdisk manager

The script `zdisk` creates a compressed ramdisk (using `zram`devices) which can be persisted in a `squashfs` filesystem, which can be restored on boot.

In this way we have the benefits of a ramdisk (speed, less stress for SSD drives), less memory usage (thanks to the `zram` devices) and without loosing contents on power off.

Moreover, the ramdisk can be very big: everytime the ramdisk contents are saved, they are added to the `squashfs` archive and the used ram becomes free (after a service restart).


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

# Tests

In the `test` directory there is a test using the [BATS](https://github.com/bats-core/bats-core) framework and some extensions.

To run the tests you need to checkout some submodules (the test framework) with the following commands:

```bash
    git submodule init
    git submodule update
```

Next, you can run the tests:

```bash
    cd test
    ./zdisk.bats
```
