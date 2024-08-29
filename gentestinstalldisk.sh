#!/bin/bash

sudo modprobe nbd
sudo qemu-img create -f qcow2 image.qcow2 10G
sudo qemu-nbd --connect=/dev/nbd0 image.qcow2
