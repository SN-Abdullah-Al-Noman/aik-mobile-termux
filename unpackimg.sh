#!/bin/bash
# AIK-mobile/unpackimg: split image and unpack ramdisk
# osm0sis @ xda-developers

case $1 in
  --help) echo "...usage: unpackimg.sh <file>"; return 1;
esac;

case $0 in
  *.sh) aik="$0";;
     *) aik="$(lsof -p $$ 2>/dev/null | $busybox grep -o '/.*unpackimg.sh$')";;
esac;
export aik="$(pwd)"
export bin="$aik/bin";
export bootpatch="$bin/bootpatch"
export ker_ver="$bin/ker_ver";
export cur="$(readlink -f "$PWD")";
export busybox=$bin/busybox;
export unboot=$bin/unboot;

echo "AIK DIR: $aik"

chmod -R 755 $bin *.sh;
#chmod 644 $bin/magic $bin/androidbootimg.magic $bin/boot_signer-dexed.jar $bin/module.prop $bin/ramdisk.img $bin/avb/* $bin/chromeos/*;
chmod 644 $bin/magic $bin/androidbootimg.magic $bin/boot_signer-dexed.jar $bin/module.prop $bin/avb/* $bin/chromeos/*;

unset img
img="$1";
[ -f "$cur/$1" ] && img="$cur/$1";
if [ ! "$img" ]; then
  $busybox ls *.elf *.img *.sin 2>/dev/null |& while IFS= read -r -p line; do
    case $line in
      aboot.img|image-new.img|unlokied-new.img|unsigned-new.img) continue;;
    esac;
    img="$line";
    break;
  done;
fi;
img="$(readlink -f "$img")";
if [ ! -f "$img" ]; then
  echo "...No image file supplied.";
  return 1;
fi;

case $0 in *.sh) clear;; esac;
echo "Android Image Kitchen - UnpackImg Script";
echo "by osm0sis @ xda-developers";

file=$($busybox basename "$img");
echo ""
echo "Supplied image: $file"

if [ -d split_img -o -d ramdisk ]; then
  echo "Removing old work folders and files...";
  rm -rf ramdisk* split_img*
fi;

echo "Setting up work folders...";
echo " "
mkdir split_img ramdisk;
chmod 755 split_img ramdisk;
#echo "run remount.sh to remount the current image's unpacked ramdisk" > ramdisk/README;
#chmod 666 ramdisk/README;
#$busybox cp -fp $bin/remount.sh ramdisk/remount.sh;
#$busybox cp -f $bin/ramdisk.img split_img/.aik-ramdisk.img;

#$bin/remount.sh --mount-only || return 1;

cd "$aik/split_img";
filesize=$($busybox wc -c < "$img");
echo "$filesize" > "$file-origsize";
imgtest="$($bin/file -m $bin/androidbootimg.magic "$img" 2>/dev/null | $busybox cut -d: -f2-)";
if [ "$(echo $imgtest | $busybox awk '{ print $2 }' | $busybox cut -d, -f1)" == "signing" ]; then
  echo $imgtest | $busybox awk '{ print $1 }' > "$file-sigtype";
  sigtype=$($busybox cat "$file-sigtype");
  echo "...Signature with \"$sigtype\" type detected, removing...";
  case $sigtype in
    BLOB)
      $busybox cp -f "$img" "$file";
      $bin/blobunpack "$file" | $busybox tail -n+5 | $busybox cut -d" " -f2 | $busybox dd bs=1 count=3 > "$file-blobtype" 2>/dev/null;
      $busybox mv -f "$file."* "$file";
    ;;
    CHROMEOS) $bin/futility vbutil_kernel --get-vmlinuz "$img" --vmlinuz-out "$file";;
    DHTB) $busybox dd bs=4096 skip=512 iflag=skip_bytes conv=notrunc if="$img" of="$file" 2>/dev/null;;
    NOOK)
      $busybox dd bs=1048576 count=1 conv=notrunc if="$img" of="$file-master_boot.key" 2>/dev/null;
      $busybox dd bs=1048576 skip=1 conv=notrunc if="$img" of="$file" 2>/dev/null;
    ;;
    NOOKTAB)
      $busybox dd bs=262144 count=1 conv=notrunc if="$img" of="$file-master_boot.key" 2>/dev/null;
      $busybox dd bs=262144 skip=1 conv=notrunc if="$img" of="$file" 2>/dev/null;
    ;;
    SIN*)
      $bin/sony_dump . "$img" >/dev/null;
      $busybox mv -f "$file."* "$file";
      rm -f "$file-sigtype";
    ;;
  esac;
  img="$file";
fi;

imgtest="$($bin/file -m $bin/androidbootimg.magic "$img" 2>/dev/null | $busybox cut -d: -f2-)";
if [ "$(echo $imgtest | $busybox awk '{ print $2 }' | $busybox cut -d, -f1)" == "bootimg" ]; then
  [ "$(echo $imgtest | $busybox awk '{ print $3 }')" == "PXA" ] && typesuffix=-PXA;
  echo "$(echo $imgtest | $busybox awk '{ print $1 }')$typesuffix" > "$file-imgtype";
  imgtype=$($busybox cat "$file-imgtype");
else
  cd $aik;
  echo "...Unrecognized format.";
  exit;
fi;
echo "...Image type: $imgtype";

case $imgtype in
  AOSP*|ELF|KRNL|OSIP|U-Boot) ;;
  *)
    cd ..;
    echo "...Unsupported format.";
    exit;
  ;;
esac;

case $(echo $imgtest | $busybox awk '{ print $3 }') in
  LOKI)
    echo $imgtest | $busybox awk '{ print $5 }' | $busybox cut -d\( -f2 | $busybox cut -d\) -f1 > "$file-lokitype";
    lokitype=$($busybox cat "$file-lokitype");
    echo "...Loki patch with \"$lokitype\" type detected, reverting...";
    echo "...Warning: A dump of your device's aboot.img is required to re-Loki!";
    $bin/loki_tool unlok "$img" "$file" >/dev/null;
    img="$file";
  ;;
  AMONET)
    echo "...Amonet patch detected, reverting...";
    $busybox dd bs=2048 count=1 conv=notrunc if="$img" of="$file-microloader.bin" 2>/dev/null;
    $busybox dd bs=1024 skip=1 conv=notrunc if="$file-microloader.bin" of="$file-head" 2>/dev/null;
    $busybox truncate -s 1024 "$file-microloader.bin";
    $busybox truncate -s 2048 "$file-head";
    $busybox dd bs=2048 skip=1 conv=notrunc if="$img" of="$file-tail" 2>/dev/null;
   $busybox cat "$file-head" "$file-tail" > "$file";
    rm -f "$file-head" "$file-tail";
    img="$file";
  ;;
esac;

tailtest="$($busybox dd if="$img" iflag=skip_bytes skip=$(($(wc -c < "$img") - 8192)) bs=8192 count=1 2>/dev/null | $bin/file -m $bin/androidbootimg.magic - 2>/dev/null | $busybox cut -d: -f2-)";
case $tailtest in
  *data)
    trim=$($busybox od -Ad -tx8 "$img" | $busybox tail -n3 | $busybox sed 's/*/-/g');
    if [ "$(echo $trim | $busybox awk '{ print $(NF-3) $(NF-2) $(NF-1) }')" == "00000000000000000000000000000000-" ]; then
      offset=$(echo $trim | $busybox awk '{ print $(NF-4) }');
    else
      offset=$(echo $trim | $busybox awk '{ print $NF }');
    fi;
    tailtest="$($busybox dd if="$img" iflag=skip_bytes skip=$((offset - 8192)) bs=8192 count=1 2>/dev/null | $bin/file -m $bin/androidbootimg.magic - 2>/dev/null | $busybox cut -d: -f2-)";
  ;;
esac;
tailtype="$(echo $tailtest | $busybox awk '{ print $1 }')";
case $tailtype in
  AVB*)
    echo "...Signature with \"$tailtype\" type detected.";
    case $tailtype in
      *v1)
        echo $tailtype > "$file-sigtype";
        echo $tailtest | $busybox awk '{ print $4 }' > "$file-avbtype";
      ;;
    esac;
  ;;
  Bump|SEAndroid)
    echo "...Footer with \"$tailtype\" type detected.";
    echo $tailtype > "$file-tailtype";
  ;;
esac;

if [ "$imgtype" == "U-Boot" ]; then
  imgsize=$(($($busybox printf '%d\n' 0x$($busybox hexdump -n 4 -s 12 -e '16/1 "%02x""\n"' "$img")) + 64));
  if [ "$filesize" != "$imgsize" ]; then
    echo "...Trimming...";
    $busybox dd bs=$imgsize count=1 conv=notrunc if="$img" of="$file" 2>/dev/null;
    img="$file";
  fi;
fi;

echo '...Splitting image to "split_img/"...';
echo " "
case $imgtype in
  AOSP_VNDR) vendor=vendor_;;
esac;
case $imgtype in
  AOSP|AOSP_VNDR) #$bin/unpackbootimg -i "$img" &> /dev/null
  
  $unboot --boot_img "$img" --out config --format mkbootimg > conf.txt
  #$unboot --boot_img "$img" --out config --format mkbootimg > conf1.txt
 
$busybox cp -f conf.txt config/conf.txt
#$busybox cp -f conf1.txt config/conf1.txt
if [ -f config/bootconfig ]; then
$busybox cp -f config/bootconfig ./
fi

  #if [ ! -z "$($busybox awk '/vendor boot image header version:/ { print $6 }' $](pwd)/split_img/config/conf.txt)" == "4" ]; then
  
 aik_new_dir="$aik/split_img"
 r_dir="$aik"
 ram_dir="$aik/split_img/config"
 #echo "1" > "$ram_dir"/SETPERM.txt
 #/data/local/python31/usr/bin/extract-dtb "$ram_dir"/dtb -o "$ram_dir" &> /dev/null
 if [ ! -z "$($busybox cat "$ram_dir"/conf.txt | $busybox grep "boot magic: VNDRBOOT")" ]; then
  v_b="1"
  fi
 
 header_version="$($busybox awk '/vendor boot image header version:/ { print $6 }' "$ram_dir"/conf.txt)"
 
 if [ "$v_b" == "1" ]; then
 $bin/unpackbootimg -i "$img" &> /dev/null
 
  [ "$header_version" == "4" ] && echo "0" > config/MAG.txt;

 echo
 print_cmdline=$($busybox cat config/conf.txt | $busybox grep "^\--vendor_cmdline" | $busybox sed 's!^--vendor_cmdline !!')
 echo "cmdline = $print_cmdline"
 
 print_board=$($busybox cat config/conf.txt | $busybox awk '/^\--board/ { print $2 }')
 echo  "board = $print_board"
 
 print_base=$($busybox cat config/conf.txt | $busybox grep "^\--base")
 echo "$print_base" | $busybox sed 's!^--!!' | $busybox awk '{ print $1" ""="" "$2}'
 
 print_pagesize=$($busybox cat config/conf.txt | $busybox grep "^\--pagesize")
 echo "$print_pagesize" | $busybox sed 's!^--!!' | $busybox awk '{ print $1" ""="" "$2}'
 
 print_kerneloff=$($busybox cat config/conf.txt | $busybox grep "^\--kernel_offset")
 echo "$print_kerneloff" | $busybox sed 's!^--!!' | $busybox awk '{ print $1" ""="" "$2}'
 
 print_ramdiskoff=$($busybox cat config/conf.txt | $busybox grep "^\--ramdisk_offset")
 echo "$print_ramdiskoff" | $busybox sed 's!^--!!' | $busybox awk '{ print $1" ""="" "$2}'
 
 print_tagsoff=$($busybox cat config/conf.txt | $busybox grep "^\--tags_offset")
 echo "$print_tagsoff" | $busybox sed 's!^--!!' | $busybox awk '{ print $1" ""="" "$2}'
 
 print_dtboff=$($busybox cat config/conf.txt | $busybox grep "^\--dtb_offset")
 echo "$print_dtboff" | $busybox sed 's!^--!!' | $busybox awk '{ print $1" ""="" "$2}'
 
 print_hdrver="--header_version $header_version"
 echo "$print_hdrver" | $busybox sed 's!^--!!' | $busybox awk '{ print $1" ""="" "$2}'
 
 else
 $bin/unpackbootimg -i "$img"
 fi
 
 cd "$ram_dir"
 
 #$busybox ls *_dtb* | while read a; do
 #rem_name="$(echo "$a" | $busybox awk -F"_" '{ print "dtb_"$1 }')"
#$busybox mv -f "$a" "$rem_name"
#done
#$busybox rm -f 00_kernel
 
 if [ ! -z "$($busybox find -type f | $busybox grep "ramdisk01")" ]; then
 #echo "true" > fragment.txt
 frag_real="true"
 > perm00.txt
 > perm01.txt
$busybox find -name "*ramdisk[0-9][0-9]" -type f | while read rd; do
 name_rd="$(echo "$rd" | $busybox grep -o "ramdisk[0-9]*")"
 r_num="$(echo "$name_rd" | $busybox sed 's!ramdisk!!')"
 "$bin"/file -m "$bin"/magic "$rd" 2>/dev/null | $busybox cut -d: -f2 | $busybox awk '{ print $1 }' > "$name_rd"_dec.log
 
 compout="$($busybox cat "$name_rd"_dec.log)"
 
 $ker_ver "${aik}/split_img/$file-kernel"

case "$compout" in
    gzip) compout=gz;;
    lzop) compout=lzo;;
    xz|lz4|lzma) compout="$compout";;
    bzip2) compout=bz2;;
    lz4-l) compout=lz4;;
    *) exit 1;;
  esac;
  compout=".$compout"
echo "$name_rd"-new.cpio"$compout" > REPLACE_"$name_rd".txt

 rm -rf "$r_dir"/"$name_rd"
 mkdir "$r_dir"/"$name_rd"
 cd "$r_dir"/"$name_rd"

 $bootpatch decompress "$ram_dir"/"$rd" "$ram_dir"/"$rd".cpio  && $bootpatch cpio "$ram_dir"/"$rd".cpio extract || $bootpatch cpio "$ram_dir"/"$rd" extract
 
 #$busybox find | $busybox xargs $busybox stat -c '%n %u %g %a' | $busybox sed 's!^./!!' >> "$ram_dir"/perm"$r_num".txt
 
 cd "$r_dir"
 $busybox find "$name_rd" -type d -o -type f | $busybox xargs $busybox stat -c '%n %u %g %a' | $busybox sed 's!^./!!' >> "$ram_dir"/perm"$r_num".txt
 cd "$ram_dir"
done
 cd "$aik_new_dir"
 echo " Удалить *ramdisk01 или ramdisk01_dec.log" > config/DELETE_ramdisk01.txt
 echo "0" > config/UNITE_ramdisk.txt
 
 else
 #echo "false" > fragment.txt
 frag_real="false"
 cd "$aik_new_dir"
 fi;;
 #fi

  AOSP-PXA) $bin/pxa-unpackbootimg -i "$img";;
  ELF)
    mkdir elftool_out;
    $bin/elftool unpack -i "$img" -o elftool_out >/dev/null;
    $busybox mv -f elftool_out/header "$file-header" 2>/dev/null;
    rm -rf elftool_out;
    $bin/unpackelf -i "$img";
  ;;
  KRNL) $busybox dd bs=4096 skip=8 iflag=skip_bytes conv=notrunc if="$img" of="$file-ramdisk" 2>&1 | $busybox tail -n+3 | $busybox cut -d" " -f1-2;;
  OSIP)
    $bin/mboot -u -f "$img";
    [ $? != 0 ] && error=1;
    for i in bootstub cmdline.txt hdr kernel parameter ramdisk.cpio.gz sig; do
      $busybox mv -f $i "$file-$($busybox basename $i .txt | $busybox sed -e 's/hdr/header/' -e 's/ramdisk.cpio.gz/ramdisk/')" 2>/dev/null || true;
    done;
  ;;
  U-Boot)
    $bin/dumpimage -l "$img";
    $bin/dumpimage -l "$img" > "$file-header";
    $busybox grep "Name:" "$file-header" | $busybox cut -c15- > "$file-name";
    $busybox grep "Type:" "$file-header" | $busybox cut -c15- | $busybox cut -d" " -f1 > "$file-arch";
    $busybox grep "Type:" "$file-header" | $busybox cut -c15- | $busybox cut -d" " -f2 > "$file-os";
    $busybox grep "Type:" "$file-header" | $busybox cut -c15- | $busybox cut -d" " -f3 | $busybox cut -d- -f1 > "$file-type";
    $busybox grep "Type:" "$file-header" | $busybox cut -d\( -f2 | $busybox cut -d\) -f1 | $busybox cut -d" " -f1 | $busybox cut -d- -f1 > "$file-comp";
    $busybox grep "Address:" "$file-header" | $busybox cut -c15- > "$file-addr";
    $busybox grep "Point:" "$file-header" | $busybox cut -c15- > "$file-ep";
    rm -f "$file-header";
    $bin/dumpimage -p 0 -o "$file-kernel" "$img";
    [ $? != 0 ] && error=1;
    case $($busybox cat "$file-type") in
      Multi) $bin/dumpimage -p 1 -o "$file-ramdisk" "$img";;
      RAMDisk) $busybox mv -f "$file-kernel" "$file-ramdisk";;
      *) touch "$file-ramdisk";;
    esac;
  ;;
esac;

if [ -f *-kernel ] && [ "$($bin/file -m $bin/androidbootimg.magic *-kernel 2>/dev/null | $busybox cut -d: -f2 | $busybox awk '{ print $1 }')" == "MTK" ]; then
  mtk=1;
  echo "\n...MTK header found in kernel, removing...";
  $busybox dd bs=512 skip=1 conv=notrunc if="$file-kernel" of=tempkern 2>/dev/null;
  $busybox mv -f tempkern "$file-kernel";
fi;
mtktest="$($bin/file -m $bin/androidbootimg.magic *-*ramdisk 2>/dev/null | $busybox cut -d: -f2-)";
mtktype=$(echo $mtktest | $busybox awk '{ print $3 }');
if [ "$(echo $mtktest | $busybox awk '{ print $1 }')" == "MTK" ]; then
  if [ ! "$mtk" ]; then
    echo "...Warning: No MTK header found in kernel!";
    mtk=1;
  fi;
  echo "...MTK header found in \"$mtktype\" type ramdisk, removing...";
  $busybox dd bs=512 skip=1 conv=notrunc if="$(ls *-*ramdisk)" of=temprd 2>/dev/null;
  $busybox mv -f temprd "$(ls *-*ramdisk)";
else
  if [ "$mtk" ]; then
    if [ ! "$mtktype" ]; then
      echo '...Warning: No MTK header found in ramdisk, assuming "rootfs" type!';
      mtktype="rootfs";
    fi;
  fi;
fi;
[ "$mtk" ] && echo $mtktype > "$file-mtktype";

if [ -f *-dt ]; then
  dttest="$($bin/file -m $bin/androidbootimg.magic *-dt 2>/dev/null | $busybox cut -d: -f2 | $busybox awk '{ print $1 }')";
  echo $dttest > "$file-dttype";
  if [ "$imgtype" == "ELF" ]; then
    case $dttest in
      QCDT|ELF) ;;
      *) echo "\n...Non-QC DTB found, packing kernel and appending...";
         $busybox gzip "$file-kernel";
         $busybox mv -f "$file-kernel.gz" "$file-kernel";
        $busybox cat "$file-dt" >> "$file-kernel";
         rm -f "$file-dt"*;;
    esac;
  fi;
fi;

$bin/file -m $bin/magic *-*ramdisk 2>/dev/null | $busybox cut -d: -f2 | $busybox awk '{ print $1 }' > "$file-${vendor}ramdiskcomp";
ramdiskcomp=`$busybox cat *-*ramdiskcomp`;
unpackcmd="$busybox $ramdiskcomp -dc";
compext=$ramdiskcomp;
case $ramdiskcomp in
  gzip) compext=gz;;
  lzop) compext=lzo;;
  xz) unpackcmd="$bin/xz -dc";;
  lzma) unpackcmd="$bin/xz -dc";;
  bzip2) compext=bz2;;
  lz4) unpackcmd="$bin/lz4 -dcq";;
  lz4-l) unpackcmd="$bin/lz4 -dcq"; compext=lz4;;
  cpio) unpackcmd="$busybox cat"; compext="";;
  empty) compext=empty;;
  *) compext="";;
esac;
if [ "$compext" ]; then
  compext=.$compext;
fi;
$busybox mv -f "$(ls *-*ramdisk)" "$file-${vendor}ramdisk.cpio$compext" 2>/dev/null;
cd ..;
if [ "$ramdiskcomp" == "data" ]; then
  echo "...Unrecognized format.";
  return 1;
fi;

if [ "$ramdiskcomp" == "empty" ]; then
  echo "Warning: No ramdisk found to be unpacked!";
else
  echo "Unpacking ramdisk to ${aik}/ramdisk/"
  echo "Compression used: $ramdiskcomp"
  $ker_ver "$aik/split_img/$file-kernel"
  if [ ! "$compext" -a ! "$ramdiskcomp" == "cpio" ]; then
    echo "...Unsupported format.";
    return 1;
  fi;
  #cd ramdisk;
  #$busybox rm -rf lost+found
  #$unpackcmd "$aik/split_img/$file-${vendor}ramdisk.cpio$compext" | EXTRACT_UNSAFE_SYMLINKS=1 cpio -i -d 2>&1;
  
  cd ramdisk;
  $busybox rm -rf lost+found
  $bootpatch decompress $aik/split_img/$file-${vendor}ramdisk.cpio$compext $aik/split_img/$file-${vendor}ramdisk_m.cpio &>/dev/null && $bootpatch cpio $aik/split_img/$file-${vendor}ramdisk_m.cpio extract &>/dev/null || $bootpatch cpio $aik/split_img/$file-${vendor}ramdisk.cpio$compext extract &>/dev/null
  
  
  if [ $? != 0 ]; then
    cd ..;
    exit 1;
  fi;
  cd ..;
  $busybox find ramdisk -type d -o -type f | $busybox xargs $busybox stat -c '%n %u %g %a' | $busybox sed 's!^./!!' >> "$aik"/split_img/config/perm.txt
  #echo "ramdisk-new.cpio$compext" > split_img/config/OUTNEW_ramdisk.txt
  if [ "$header_version" == "4" -a "$frag_real" == "false" -a -s "$ram_dir"/*ramdisk00  ]; then
  echo " ramdisk01-new.cpio$compext" > $aik/split_img/config/ADDNEW_ramdisk01.txt
  echo " ramdisk-new.cpio$compext" > $aik/split_img/config/REPLACE_ramdisk.txt
  elif [ "$header_version" == "4" -a "$frag_real" == "false" -a ! -s "$ram_dir"/*ramdisk00  ]; then
  echo " ramdisk-new.cpio$compext" > $aik/split_img/config/REPLACE_ramdisk.txt
    elif [ "$header_version" != "4" -a "$frag_real" == "false" ]; then
  echo " ramdisk-new.cpio$compext" > $aik/split_img/config/REPLACE_ramdisk.txt
  fi
 fi;
 echo ""
 
echo "Done!"
