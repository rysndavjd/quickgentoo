#!/bin/bash

dd if=/dev/zero of=./loopfile bs=1024 count=10000000

losetup /dev/loop0 ./loopfile
mount /dev/loop0 ./mnt
