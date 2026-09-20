#!/bin/bash
# AIK-mobile/remount: reload current unpacked ramdisk
# osm0sis @ xda-developers

case $1 in
  --help) echo "usage: remount.sh [--mount-only|--umount-only]"; return 1;
esac;

case $0 in
  *.sh) rd="$0";;
     *) rd="$(lsof -p $$ 2>/dev/null | $busybox grep -o '/.*remount.sh$')";;
esac;
rd="$(dirname "$(readlink -f "$rd")")";
cd "$rd"; cd ..;
aik="$(pwd)";
bin="$aik/bin";
busybox=$bin/busybox;

chmod -R 755 $bin $aik/*.sh;
chmod 644 $bin/magic $bin/androidbootimg.magic $bin/boot_signer-dexed.jar $bin/module.prop $bin/ramdisk.img $bin/avb/* $bin/chromeos/*;

[ ! -f $busybox ] && busybox=busybox;

su=sh;
$busybox ps | $busybox grep -v grep | $busybox grep -q zygote && su="su -mm";

--mount-only() {
  $busybox mount | $busybox grep -q " $aik/ramdisk " && return 0;
  $su -c "$busybox mount -t ext4 -o rw,noatime $aik/split_img/.aik-ramdisk.img $aik/ramdisk" 2>/dev/null;
  if [ $? != 0 ]; then
    minorx=1;
    [ -e /dev/block/loop1 ] && minorx=$(ls -l /dev/block/loop1 | $busybox awk '{ print $6 }');
    i=0;
    while [ $i -lt 64 ]; do
      loop=/dev/block/loop$i;
      $busybox mknod $loop b 7 $((i * minorx)) 2>/dev/null;
      $busybox losetup $loop $aik/split_img/.aik-ramdisk.img 2>/dev/null;
      $busybox losetup $loop | $busybox grep -q .aik-ramdisk.img && break;
      i=$((i + 1));
    done;
    $su -c "$busybox mount -t ext4 -o loop,noatime $loop $aik/ramdisk";
    if [ $? != 0 ]; then
      $busybox losetup -d $loop 2>/dev/null;
      return 1;
    fi;
  fi;
}

--umount-only() {
  loop=$($busybox mount | $busybox grep $aik/ramdisk | $busybox cut -d" " -f1);
  
  pid_term="$($busybox cat /proc/$$/status | $busybox awk '/^PPid:/ { print $2 }')"
 fuser -vm "$loop" &> $bin/fuser.txt
 
 check_pid="$($busybox cat $bin/fuser.txt | $busybox grep -o "$pid_term")"
 if [ -z "$check_pid" ]; then
 fuser -skm "$loop"
  $su -c "$busybox umount $aik/ramdisk";
  $busybox losetup -d $loop 2>/dev/null || true;
  fi
  $busybox rm -f $bin/fuser.txt
}

if [ "$1" ]; then
  $1 || return 1;
else
  if ! $busybox mount | $busybox grep -q " $aik/ramdisk "; then
    --mount-only || return 1;
  else
    --umount-only;
  fi;
  echo "Working ramdisk remounted.";
fi;

return 0;

