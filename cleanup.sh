#!/bin/bash
# AIK-mobile/cleanup: reset working directory
# osm0sis @ xda-developers

$bb rm -rf ramdisk* split_img *-new* || return 1
echo "Working directory cleaned."
