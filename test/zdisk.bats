#!test/libs/bats-core/bin/bats

BATSLIB_TEMP_PRESERVE=0
BATSLIB_TEMP_PRESERVE_ON_FAILURE=1

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'libs/bats-file/load'
load 'libs/bats-mock/load'

# Get the path of the zdisk script: expected in the current directory
ZDISK_PATH="$PWD"

function setup() {
    TEST_TEMP_DIR="$(temp_make)"
    zramDevice="/dev/zram0"

    export ZDISK_SIZE="1024K"
    export ROOT="${TEST_TEMP_DIR}"
    export USE_PBZIP2="false" # don't use pbzip2 during tests

    SAVED_DISK="${ROOT}/var/lib/zdisk"
    ZDISK_MOUNTPOINT="${ROOT}/mnt/zdisk"
    OVR_LOWER="${ROOT}/tmp/.zdisk/squashed"
    OVR_ZRAM="${ROOT}/tmp/.zdisk/zram"
    QUICKSAVE_FILE="${SAVED_DISK}.ovr.tbz2"
}

function teardown() {
   temp_del "${TEST_TEMP_DIR}"
}

# Extra assertions
#-----------------

# assert that the argument exists and it is a directory
function assert_dir_exist() {
  local -r file="$1"
  
  if [[ ! -e "$file" ]]; then
    local -r rem="$BATSLIB_FILE_PATH_REM"
    local -r add="$BATSLIB_FILE_PATH_ADD"
    batslib_print_kv_single 4 'path' "${file/$rem/$add}" \
      | batslib_decorate 'directory does not exist' \
      | fail
  elif [[ ! -d "$file" ]]; then
    local -r rem="$BATSLIB_FILE_PATH_REM"
    local -r add="$BATSLIB_FILE_PATH_ADD"
    batslib_print_kv_single 4 'path' "${file/$rem/$add}" \
      | batslib_decorate 'the path is not a directory' \
      | fail
  fi
}

# Utilities
#----------

# Same as touch, but creates the path if does not exist
function touchFile() {
    for f in $@; do
        mkdir -p $(dirname "$f")
        touch "$f"
    done
}

# Fills the ramdisk with some file
function fillRamdisk() {
    touchFile "${OVR_ZRAM}/upper/test_file.txt"
}

# Prepares a tbz2 archive to be loaded into ramdisk
function create_quickSaved_archive() {
    local TBZ2_TEMP_DIR="${TEST_TEMP_DIR}/tbz_build"

    mkdir -p $(dirname "${SAVED_DISK}") "${TBZ2_TEMP_DIR}"
    date > "${TBZ2_TEMP_DIR}/saved_file.txt"
    tar -C "${TBZ2_TEMP_DIR}" -jcf "${QUICKSAVE_FILE}" .
}

# Tests
#------

@test "Help page" {
    run ${ZDISK_PATH}/zdisk help

    assert_success
    assert_line --index 0 --partial "Persistent compressed ramdisk manager v" 
}

@test "Start, already mounted" {
    stub grep "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true"
    
    run ${ZDISK_PATH}/zdisk start 
    
    assert_failure 1
    assert_output "Disk already mounted"
    
    unstub grep || fail "$output"
}

@test "Start, not mounted, not restored" {
    export RESTORE_ON_START="false"
    
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : false"
    stub modprobe "overlay : true" \
                  "zram num_devices=4 : true"
    stub zramctl  "-f : echo '${zramDevice}'" \
                  "${zramDevice} -s ${ZDISK_SIZE} -a lzo : true"
    stub mkfs     "-t xfs ${zramDevice} : true"
    stub mount    "${zramDevice} ${ZDISK_MOUNTPOINT}"
    
    run ${ZDISK_PATH}/zdisk start
    
    assert_success
    assert_dir_exist "${ZDISK_MOUNTPOINT}"
    
    unstub mount    || fail "$output"
    unstub mkfs     || fail "$output"
    unstub zramctl  || fail "$output"
    unstub modprobe || fail "$output"
    unstub grep     || fail "$output"
}

@test "Start, not mounted, restored but not previously saved" {
    export RESTORE_ON_START="true"
    
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : false"
    stub modprobe "overlay : true" \
                  "zram num_devices=4 : true"
    stub zramctl  "-f : echo '${zramDevice}'" \
                  "${zramDevice} -s ${ZDISK_SIZE} -a lzo : true"
    stub mkfs     "-t xfs ${zramDevice} : true"
    stub mount    "${zramDevice} ${ZDISK_MOUNTPOINT}"
    
    run ${ZDISK_PATH}/zdisk start
    
    assert_success
    assert_dir_exist "${ZDISK_MOUNTPOINT}"

    unstub mount    || fail "$output"
    unstub mkfs     || fail "$output"
    unstub zramctl  || fail "$output"
    unstub modprobe || fail "$output"
    unstub grep     || fail "$output"
}

@test "Start, not mounted, restored from saved" {
    export RESTORE_ON_START="true"
    
    touchFile "${SAVED_DISK}.sqfs"
    
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : false"
    stub modprobe "overlay : true" \
                  "zram num_devices=4 : true"
    stub zramctl  "-f : echo '${zramDevice}'" \
                  "${zramDevice} -s $ZDISK_SIZE -a lzo : true"
    stub mkfs     "-t xfs ${zramDevice} : true"
    stub mount    "${zramDevice} ${OVR_ZRAM}" \
                  "-t squashfs ${SAVED_DISK}.sqfs ${OVR_LOWER}"  \
                  "-t overlay -o lowerdir=${OVR_LOWER},upperdir=${OVR_ZRAM}/upper,workdir=${OVR_ZRAM}/work overlayfs ${ZDISK_MOUNTPOINT}"
    
    run ${ZDISK_PATH}/zdisk start

    assert_success
    assert_dir_exist "${ZDISK_MOUNTPOINT}"
    assert_dir_exist "${OVR_LOWER}" 
    assert_dir_exist "${OVR_ZRAM}"
    assert_dir_exist "${OVR_ZRAM}/upper"
    assert_dir_exist "${OVR_ZRAM}/work"

    unstub mount    || fail "$output"
    unstub mkfs     || fail "$output"
    unstub zramctl  || fail "$output"
    unstub modprobe || fail "$output"
    unstub grep     || fail "$output"
}

@test "Start, not mounted, restored from quick saved" {
    export RESTORE_ON_START="true"
    
    create_quickSaved_archive
    
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : false"
    stub modprobe "overlay : true" \
                  "zram num_devices=4 : true"
    stub zramctl  "-f : echo '${zramDevice}'" \
                  "${zramDevice} -s $ZDISK_SIZE -a lzo : true"
    stub mkfs     "-t xfs ${zramDevice} : true"
    stub mount    "${zramDevice} ${ZDISK_MOUNTPOINT}"
    
    run ${ZDISK_PATH}/zdisk start
    
    assert_success
    assert_dir_exist       "${ZDISK_MOUNTPOINT}"
    assert_file_exist      "${ZDISK_MOUNTPOINT}/saved_file.txt"
    assert_file_not_exist  "${OVR_LOWER}" 
    assert_file_not_exist  "${OVR_ZRAM}"
    assert_file_not_exist  "${OVR_ZRAM}/upper"
    assert_file_not_exist  "${OVR_ZRAM}/work"

    unstub mount    || fail "$output"
    unstub mkfs     || fail "$output"
    unstub zramctl  || fail "$output"
    unstub modprobe || fail "$output"
    unstub grep     || fail "$output"
}

@test "Start, not mounted, restored from saved and quick saved" {
    export RESTORE_ON_START="true"
    
    touchFile "${SAVED_DISK}.sqfs"
    create_quickSaved_archive
    
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : false"
    stub modprobe "overlay : true" \
                  "zram num_devices=4 : true"
    stub zramctl  "-f : echo '${zramDevice}'" \
                  "${zramDevice} -s $ZDISK_SIZE -a lzo : true"
    stub mkfs     "-t xfs ${zramDevice} : true"
    stub mount    "${zramDevice} ${OVR_ZRAM}" \
                  "-t squashfs ${SAVED_DISK}.sqfs ${OVR_LOWER}"  \
                  "-t overlay -o lowerdir=${OVR_LOWER},upperdir=${OVR_ZRAM}/upper,workdir=${OVR_ZRAM}/work overlayfs ${ZDISK_MOUNTPOINT}"
    
    run ${ZDISK_PATH}/zdisk start
    
    assert_success
    assert_dir_exist  "${OVR_LOWER}" 
    assert_dir_exist  "${OVR_ZRAM}"
    assert_dir_exist  "${OVR_ZRAM}/upper"
    assert_dir_exist  "${OVR_ZRAM}/work"
    assert_dir_exist  "${ZDISK_MOUNTPOINT}"
    assert_file_exist "${ZDISK_MOUNTPOINT}/saved_file.txt"

    unstub mount    || fail "$output"
    unstub mkfs     || fail "$output"
    unstub zramctl  || fail "$output"
    unstub modprobe || fail "$output"
    unstub grep     || fail "$output"
}

@test "Start, named service" {
    SAVED_DISK="${ROOT}/var/lib/test-zdisk"
    ZDISK_MOUNTPOINT="${ROOT}/mnt/test-zdisk"
    OVR_LOWER="${ROOT}/tmp/.test-zdisk/squashed"
    OVR_ZRAM="${ROOT}/tmp/.test-zdisk/zram"
    QUICKSAVE_FILE="${SAVED_DISK}.ovr.tbz2"

    export RESTORE_ON_START="true"

    mkdir -p "${ROOT}/usr/local/bin"
    cp ${ZDISK_PATH}/zdisk "${ROOT}/usr/local/bin/test-zdisk"
    
    touchFile "${SAVED_DISK}.sqfs"
    
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : false"
    stub modprobe "overlay : true" \
                  "zram num_devices=4 : true"
    stub zramctl  "-f : echo '${zramDevice}'" \
                  "${zramDevice} -s $ZDISK_SIZE -a lzo : true"
    stub mkfs     "-t xfs ${zramDevice} : true"
    stub mount    "${zramDevice} ${OVR_ZRAM}" \
                  "-t squashfs ${SAVED_DISK}.sqfs ${OVR_LOWER}"  \
                  "-t overlay -o lowerdir=${OVR_LOWER},upperdir=${OVR_ZRAM}/upper,workdir=${OVR_ZRAM}/work overlayfs ${ZDISK_MOUNTPOINT}"

    run "${ROOT}/usr/local/bin/test-zdisk" start

    assert_success
    assert_dir_exist "${ZDISK_MOUNTPOINT}"
    assert_dir_exist "${OVR_LOWER}"
    assert_dir_exist "${OVR_ZRAM}"
    assert_dir_exist "${OVR_ZRAM}/upper"
    assert_dir_exist "${OVR_ZRAM}/work"

    unstub mount    || fail "$output"
    unstub mkfs     || fail "$output"
    unstub zramctl  || fail "$output"
    unstub modprobe || fail "$output"
    unstub grep     || fail "$output"
}

@test "Stop, not monted" {
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : false"
    
    run ${ZDISK_PATH}/zdisk stop
    
    assert_output  "Disk not mounted"
    assert_failure 1
    
    unstub grep || failt "$output"
}

@test "Stop without save, only ramdisk" {
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true" \
                  "${ZDISK_MOUNTPOINT} /etc/mtab : echo '${zramDevice}'"
    stub umount   "${ZDISK_MOUNTPOINT}"
    stub zramctl  "-r ${zramDevice}"
    
    run ${ZDISK_PATH}/zdisk stop --nosave
    
    assert_success
    
    unstub zramctl || fail "$output"
    unstub umount  || fail "$output"
    unstub grep    || fail "$output"
}

@test "Stop without save, ramdisk and squashed" {
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true" \
                  "${ZDISK_MOUNTPOINT} /etc/mtab : echo 'overlayfs ${ZDISK_MOUNTPOINT} overlay rw,relatime,lowerdir=${OVR_LOWER},upperdir=${OVR_ZRAM}/upper,workdir=${OVR_ZRAM}/work 0 0'" \
                  "${OVR_ZRAM} /etc/mtab : echo '/dev/zram0 /tmp/.zdisk/zram xfs rw,relatime,attr2,inode64,noquota 0 0'"
    stub umount   "${ZDISK_MOUNTPOINT}" \
                  "${OVR_ZRAM}" \
                  "${OVR_LOWER}"
    stub zramctl  "-r ${zramDevice}"
    
    run ${ZDISK_PATH}/zdisk stop --nosave
    
    assert_success
    
    unstub zramctl || fail "$output"
    unstub umount  || fail "$output"
    unstub grep    || fail "$output"
}

@test "Stop with save, ramdisk and squashed" {
    fillRamdisk
    touchFile "${SAVED_DISK}.tmp.sqfs"
    mkdir -p "${ZDISK_MOUNTPOINT}"
    
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true" \
                  "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true" \
                  "${ZDISK_MOUNTPOINT} /etc/mtab : echo 'overlayfs ${ZDISK_MOUNTPOINT} overlay rw,relatime,lowerdir=${OVR_LOWER},upperdir=${OVR_ZRAM}/upper,workdir=${OVR_ZRAM}/work 0 0'" \
                  "${OVR_ZRAM} /etc/mtab : echo '/dev/zram0 /tmp/.zdisk/zram xfs rw,relatime,attr2,inode64,noquota 0 0'"
    stub losetup  "-j ${SAVED_DISK}.sqfs : echo '${zramDevice}: [64262]:136990 (${SAVED_DISK}.sqfs)'"
    stub umount   "${ZDISK_MOUNTPOINT}" \
                  "${OVR_ZRAM}" \
                  "${OVR_LOWER}"
    stub zramctl  "-r ${zramDevice}"
    
    run ${ZDISK_PATH}/zdisk stop
    
    assert_success
    assert_output --partial "Restoring ${SAVED_DISK}.sqfs from ${SAVED_DISK}.tmp.sqfs"
    assert_file_not_exist "${SAVED_DISK}.tmp.sqfs"
    assert_file_exist     "${SAVED_DISK}.sqfs"
    
    unstub zramctl || fail "$output"
    unstub umount  || fail "$output"
    unstub losetup || fail "$output"
    unstub grep    || fail "$output"
}

@test "Stop with save, ramdisk and squashed, named service" {
    SAVED_DISK="${ROOT}/var/lib/test-zdisk"
    ZDISK_MOUNTPOINT="${ROOT}/mnt/test-zdisk"
    OVR_LOWER="${ROOT}/tmp/.test-zdisk/squashed"
    OVR_ZRAM="${ROOT}/tmp/.test-zdisk/zram"
    QUICKSAVE_FILE="${SAVED_DISK}.ovr.tbz2"

    mkdir -p "${ROOT}/usr/local/bin"
    cp ${ZDISK_PATH}/zdisk "${ROOT}/usr/local/bin/test-zdisk"

    fillRamdisk
    touchFile "${SAVED_DISK}.tmp.sqfs"
    mkdir -p "${ZDISK_MOUNTPOINT}"
    
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true" \
                  "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true" \
                  "${ZDISK_MOUNTPOINT} /etc/mtab : echo 'overlayfs ${ZDISK_MOUNTPOINT} overlay rw,relatime,lowerdir=${OVR_LOWER},upperdir=${OVR_ZRAM}/upper,workdir=${OVR_ZRAM}/work 0 0'" \
                  "${OVR_ZRAM} /etc/mtab : echo '/dev/zram0 /tmp/.zdisk/zram xfs rw,relatime,attr2,inode64,noquota 0 0'"
    stub losetup  "-j ${SAVED_DISK}.sqfs : echo '${zramDevice}: [64262]:136990 (${SAVED_DISK}.sqfs)'"
    stub umount   "${ZDISK_MOUNTPOINT}" \
                  "${OVR_ZRAM}" \
                  "${OVR_LOWER}"
    stub zramctl  "-r ${zramDevice}"
    
    run "${ROOT}/usr/local/bin/test-zdisk" stop
    
    assert_success
    assert_output --partial "Restoring ${SAVED_DISK}.sqfs from ${SAVED_DISK}.tmp.sqfs"
    assert_file_not_exist "${SAVED_DISK}.tmp.sqfs"
    assert_file_exist     "${SAVED_DISK}.sqfs"
    
    unstub zramctl || fail "$output"
    unstub umount  || fail "$output"
    unstub losetup || fail "$output"
    unstub grep    || fail "$output"
}

@test "Save, not mounted" {
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : false"
    
    run ${ZDISK_PATH}/zdisk save
    
    assert_output  "Disk not mounted"
    assert_failure 1
    
    unstub grep    || fail "$output"
}

@test "Save, quick" {
    fillRamdisk
    mkdir -p "${ZDISK_MOUNTPOINT}"

    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true"
    
    run ${ZDISK_PATH}/zdisk save --quick
    
    assert_success
    assert_output "Doing quick backup"
    assert_file_exist "${QUICKSAVE_FILE}"
    
    unstub grep    || fail "$output"
    
    local ovr_contents="${TEST_TEMP_DIR}/ovr_contents"
    
    mkdir -p "${ovr_contents}"
    tar -C ${ovr_contents} -jxf "${QUICKSAVE_FILE}"
    
    assert_file_exist "${ovr_contents}/test_file.txt"
}

@test "Save, quick, no previously saved" {
    touchFile "${ROOT}/mnt/zdisk/test_file.txt"
    
    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true"
    
    run ${ZDISK_PATH}/zdisk save --quick
    
    assert_success
    assert_output "Doing quick backup"
    assert_file_exist "${QUICKSAVE_FILE}"
    
    unstub grep    || fail "$output"
    
    local ovr_contents="${TEST_TEMP_DIR}/ovr_contents"
    
    mkdir -p "${ovr_contents}"
    tar -C ${ovr_contents} -jxf "${QUICKSAVE_FILE}"
    
    assert_file_exist "${ovr_contents}/test_file.txt"
}

@test "Save, quick, use pbzip2" {
    fillRamdisk
    mkdir -p "${ZDISK_MOUNTPOINT}"

    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true"
    stub which    "pbzip2 : echo $(which bzip2)"
    
    export USE_PBZIP2="true" # For this test use pbzip2
    
    run ${ZDISK_PATH}/zdisk save --quick
    
    assert_success
    assert_output "Doing quick backup with pbzip2"
    assert_file_exist "${QUICKSAVE_FILE}"
    
    unstub which   || fail "$output"
    unstub grep    || fail "$output"
    
    local ovr_contents="${TEST_TEMP_DIR}/ovr_contents"
    
    mkdir -p "${ovr_contents}"
    tar -C ${ovr_contents} -jxf "${QUICKSAVE_FILE}"
    
    assert_file_exist "${ovr_contents}/test_file.txt"
}

@test "Save, full, no previously saved" {
    fillRamdisk
    mkdir -p "${ZDISK_MOUNTPOINT}"

    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true"
    stub losetup  "-j ${SAVED_DISK}.sqfs : echo ''"
    
    run ${ZDISK_PATH}/zdisk save
    
    assert_success
    assert_line --index 0 "Doing full backup"
    assert_file_exist "${SAVED_DISK}.sqfs"
    
    unstub losetup || fail "$output"
    unstub grep    || fail "$output"
}

@test "Save, full, previously saved, overwrite" {
    fillRamdisk
    mkdir -p "${ZDISK_MOUNTPOINT}"

    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true"
    stub losetup  "-j ${SAVED_DISK}.sqfs : echo '${zramDevice}: [64262]:136990 (${SAVED_DISK}.sqfs)'"
    
    run ${ZDISK_PATH}/zdisk save -overwrite
    
    assert_success || fail "$output"
    assert_line --index 0 "Destination file is mounted, saving to ${SAVED_DISK}.tmp.sqfs"
    assert_line --index 1 "Doing full backup"
    assert_file_exist "${SAVED_DISK}.tmp.sqfs"
    
    unstub losetup || fail "$output"
    unstub grep    || fail "$output"
}

@test "Save, full, previously saved and quick-saved" {
    fillRamdisk
    touchFile "${SAVED_DISK}.tmp.sqfs" "${QUICKSAVE_FILE}"
    mkdir -p "${ZDISK_MOUNTPOINT}"

    stub grep     "-q ${ZDISK_MOUNTPOINT} /etc/mtab : true"
    stub losetup  "-j ${SAVED_DISK}.sqfs : echo '${zramDevice}: [64262]:136990 (${SAVED_DISK}.sqfs)'"
    
    run ${ZDISK_PATH}/zdisk save
    
    assert_success
    assert_line --index 0 "Destination file is mounted, saving to ${SAVED_DISK}.tmp.sqfs"
    assert_line --index 1 "Doing full backup"
    assert_file_exist     "${SAVED_DISK}.tmp.sqfs"
    assert_file_not_exist "${QUICKSAVE_FILE}"
    
    unstub losetup || fail "$output"
    unstub grep    || fail "$output"
}

@test "Install, script only" {
    run ${ZDISK_PATH}/zdisk install
    
    assert_success
    assert_file_exist "${ROOT}/usr/local/bin/zdisk"
}

@test "Install, script only, no overwrite" {
    touchFile "${ROOT}/usr/local/bin/zdisk"
    
    run ${ZDISK_PATH}/zdisk install
    
    assert_success
    assert_output "Command already installed, use --force to force reinstall"
    assert_file_exist "${ROOT}/usr/local/bin/zdisk"
    assert [ $(wc -c < "${ROOT}/usr/local/bin/zdisk") -eq 0 ] # it must not be changed
}

@test "Install, script only, forced overwrite" {
    touchFile "${ROOT}/usr/local/bin/zdisk"
    
    run ${ZDISK_PATH}/zdisk install --force
    
    assert_success
    assert_file_exist "${ROOT}/usr/local/bin/zdisk"
    assert [ $(wc -c < "${ROOT}/usr/local/bin/zdisk") -gt 0 ] # it must be changed
}

@test "Install, systemd service" {
    stub systemctl "daemon-reload" \
                   "enable test-disk.service"

    run ${ZDISK_PATH}/zdisk install --systemd test-disk --autostart on
    
    assert_success
    assert_file_exist "${ROOT}/usr/local/bin/zdisk"
    assert_file_exist "${ROOT}/usr/local/bin/test-disk"
    assert_file_exist "${ROOT}/etc/systemd/system/test-disk.service"
    assert_file_exist "${ROOT}/etc/conf.d/test-disk"
    assert $(grep -q "EnvironmentFile=${ROOT}/etc/conf.d/test-disk"    "${ROOT}/etc/systemd/system/test-disk.service")
    assert $(grep -q "ExecStart=${ROOT}/usr/local/bin/test-disk start" "${ROOT}/etc/systemd/system/test-disk.service")
    assert $(grep -q "ExecStop=${ROOT}/usr/local/bin/test-disk stop"   "${ROOT}/etc/systemd/system/test-disk.service")
    assert $(grep -q "ZDISK_MOUNTPOINT=\"/mnt/test-disk\""             "${ROOT}/etc/conf.d/test-disk")
    
    unstub systemctl || fail "$output"
}

@test "Uninstall" {
    touchFile "${ROOT}/usr/local/bin/zdisk"
    
    run ${ZDISK_PATH}/zdisk uninstall
    
    assert_success
    assert_file_not_exist "${ROOT}/usr/local/bin/zdisk"
}

@test "Uninstall, systemd service" {
    touchFile "${ROOT}/usr/local/bin/zdisk" \
              "${ROOT}/usr/local/bin/test-zdisk" \
              "${ROOT}/etc/systemd/system/test-zdisk.service" \
              "${ROOT}/etc/conf.d/test-zdisk"
          
    stub systemctl "stop test-zdisk" \
                   "disable test-zdisk"
    
    run ${ZDISK_PATH}/zdisk uninstall --systemd test-zdisk
    
    assert_success
    assert_file_not_exist "${ROOT}/etc/conf.d/test-zdisk"
    assert_file_not_exist "${ROOT}/etc/systemd/system//test-zdisk.service"
    assert_file_not_exist "${ROOT}/usr/local/bin/test-zdisk"
    assert_file_exist     "${ROOT}/usr/local/bin/zdisk"

    unstub systemctl || fail "$output"
}
