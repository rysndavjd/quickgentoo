#!/bin/bash

version=0.1
PASSWORD1=""
username=""
lukspw=""
timezone="$(curl --fail https://ipapi.co/timezone)"

if [ "$(id -u)" != 0 ] ; then 
    echo "Run as root."
    exit 1
fi

help() 
{
    echo "quickarch, version $version"
    echo "Usage: quickarch [option] ..."
    echo "Options:"
    echo "      -h  (calls help menu)"
    echo "      -c  (use config)"
    exit 0

}

while getopts hc: flag; do
    case "${flag}" in
        h) help;;
        c) config=${OPTARG};;
        ?) help;;
    esac
done

#prechecks
internetfn() 
{
    echo "Checking internet access by sending a ping to Cloudflare (1.1.1.1)."
    if ping -c 1 one.one.one.one &> /dev/null ; then
        echo "Internet access is available."
    else
        echo -e "No internet access, read "https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Networking"\nOn other device, to figure out how to get online."
        exit 1
    fi
}

distrocheck() 
{
    if [ -f /etc/gentoo-release ] ; then
        echo "Gentoo media detected."
    else
        echo "Please use Gentoo Minimal Installation CD or other Gentoo based system."
        exit 1
    fi
}

architecturefn() 
{
    PS3="Select architecture to install for: "
    options=("amd64" "arm64" "Open Documentation" "Exit")
    select opt in "${options[@]}"
    do
        case $opt in
            "amd64") architecture="amd64"
            rootfscode="8304"
            qemu_user_targets="x86_64"
            LLVM_TARGETS="X86"
            clear
            break;;

            "arm64") architecture="arm64"
            rootfscode="8305"
            qemu_user_targets="aarch64"
            LLVM_TARGETS="AArch64"
            clear
            break;;

#            "riscv") architecture="riscv"
#            rootfscode="8300"
#            qemu_user_targets="riscv64"
#            LLVM_TARGETS="RISCV"
#            clear
#            break;;

            "Open Documentation") clear
            echo "I need to make the docs still."
            sleep 5
            architecturefn
            break;;

            "Exit") exit ;;
            *) echo "Wrong option please select again"; architecturefn;;
        esac
    done
}

#partitioning 

#dualboot() {
#
#}

# $1 = disk partition to get
diskpartfn() {
    case "$SELECTED_DISK" in
        #sata/scsi + ide
        sd*|hd*)
            diskpart="${SELECTED_DISK}${1}"
            ;;
        #nvme + nbd
        nvme*|nbd*)
            diskpart="${SELECTED_DISK}p${1}"
            ;;
        *)
            echo "Unknown disk type: $SELECTED_DISK"
            exit 1
            ;;
    esac
}

#fn (DISK use)
selectdiskfn() 
{
    listblk=$(lsblk -d -n -o NAME)
    PS3="Please select a disk: "
    static_options=()
    dynamic_options=()
    options=()

    static_options=("Open Documentation" "Exit")
    while read -r line ; do
        NAME=$(echo "$line")
        dynamic_options+=("$NAME")
    done <<< "$listblk"
    options=("${dynamic_options[@]}" "${static_options[@]}")

    select opt in "${options[@]}"; do
        if [[ -n "$opt" ]]; then
            SELECTED_DISK=$opt
            break
        else
            echo "Invalid selection. Please choose a valid number."
        fi
    done
    case $opt in
        "Open Documentation") clear
        echo "need to make docs"
        selectdiskfn;;

        "Exit")
        exit
        ;;
    esac
}

checkpartitionfn() 
{
    blkraw=$(blkid /dev/$1* --output device)
    blksort=$(echo $blkraw | sed "s/\/dev\/$1//")
    #for listpart in $blksort ; do
    #    echo $listpart
    #done
}

disklayoutfn() 
{
    PS3="Please select a layout: "
    options=("Normal" "LVM" "Encrypted Root+Home" "Encrypted Home" "Full Disk Encryption" "Open Documentation" "Exit")
    select opt in "${options[@]}"
    do
        case $opt in
            "Normal") disklayout="normal"
            break;;

            "LVM") disklayout="lvm"
            break;;

            "Encrypted Root+Home") disklayout="encroothome"
            break;;

            "Encrypted Home") disklayout="enchome"
            break;;
            
            "Full Disk Encryption") disklayout="fde"
            break;;

            "Open Documentation") clear
            echo "I need to make the docs still."
            sleep 5
            disklayoutfn
            break;;

            "Exit") exit ;;
            *) echo "Wrong option please select again"; disklayoutfn;;
        esac
    done
}

choosefsfn() 
{
    PS3="Please select a filesystem: "
    options=("ext4" "btrfs" "xfs" "Open Documentation" "Exit")
    select opt in "${options[@]}"
    do
        case $opt in
            "ext4") diskfs="ext4"
            break;;

            "btrfs") diskfs="btrfs"
            break;;

            "xfs") diskfs="xfs"
            break;;

            "Open Documentation") clear
            echo "I need to make the docs still."
            sleep 5
            choosefsfn
            break;;

            "Exit") exit ;;
            *) echo "Wrong option please select again"; choosefsfn;;
        esac
    done
}

formatwarningfn() 
{
    echo "Selected disk: \"$SELECTED_DISK\" listed below, verify it is correct."
    parted /dev/$SELECTED_DISK print
    read -p "Press Enter to continue..."
    sgdisk -Z /dev/$SELECTED_DISK > /dev/null
    echo "Disk has been formated."
    clear
}

# $1 = partition num
# $2 = filesystem
# $3 = if subvolume eg in /dev/mapper/home
makefsfn() 
{
    if [ $3 ] ; then 
        diskpart="mapper/$3"
    else
        diskpartfn $1
    fi
    
    partprobe /dev/"$SELECTED_DISK" 
    if [ "$2" = "fat" ] ; then 
        mkfs.fat -F32 /dev/"$diskpart"
        partprobe /dev/"$SELECTED_DISK"
    elif [ "$2" = "ext4" ] ; then
        mkfs.ext4 /dev/$diskpart > /dev/null
        partprobe /dev/"$SELECTED_DISK"
    elif [ "$2" = "btrfs" ] ; then
        mkfs.btrfs $diskpart > /dev/null
        partprobe /dev/"$SELECTED_DISK"
    fi
}

# $1 = luks version
# $2 = disk num to encrypt
encryptdiskfn() 
{
    luksv=$1
    encdisk=$2
    if [ $1 = "1" ] ; then
        #luks1 being used, assuming it is being use because upstream grub without patching, does not support luks2.
        algo="legacy"
    else
        echo "Choose a encryption algorium/pbkdf/hash to use, read docs for further info."
        PS3="Select a encryption algorium: "
        options=("serpent+argon2id+whirlpool" "serpent+pbkdf2+sha512" "aes+pbkdf2+sha512" "Open Documentation" "Exit")
        select opt in "${options[@]}"
        do
            case $opt in
                "serpent+argon2id+whirlpool") algo="saw"
                break;;

                "serpent+pbkdf2+sha512") algo="sps"
                break;;

                "aes+pbkdf2+sha512") algo="aps"
                break;;

                "Open Documentation") clear
                echo "I need to make the docs still."
                sleep 5
                encryptdiskfn
                break;;

                "Exit") exit ;;
                *) echo "Wrong option please select again"; encryptdiskfn;;
            esac
        done

        diskpartfn $2
    fi

    echo -e "Making encrypted partition on $diskpart, luks$luksv "
    read -s -p "Enter luks password: " lukspw
    echo "(this may take some time.)"
    case "$algo" in
        saw)
            echo -n "${lukspw}" | cryptsetup luksFormat --type luks2 --cipher serpent-xts-plain64 --iter-time 5000 --key-size 512 --pbkdf argon2id --use-urandom /dev/"$diskpart" --batch-mode --key-file /dev/stdin
            echo ""
            ;;
        sps)
            #echo -n "${lukspw}" | cryptsetup -y -v luksFormat
            echo ""
            ;;
        aps)
            #echo -n "${lukspw}" | cryptsetup -y -v luksFormat
            echo ""
            ;;
        legacy)
            #echo -n "${lukspw}" | cryptsetup -y -v luksFormat 
            echo ""
            ;;
        *)
            echo "Unknown disk type: $SELECTED_DISK"
            exit 1
            ;;
    esac
}

# $1 = disk num to mount
# $2 = mount point
# $3 = disk mapper name
mountdiskfn() 
{
    if [ $3 ] ; then
        diskpart="mapper/$3"
    else
        diskpartfn $1
    fi
    mount /dev/"$diskpart" "$2" --mkdir
}

# $1 = disk num to open
# $2 = luks disk name eg home
opencryptfn() 
{
    diskpartfn $1
    echo -n "${lukspw}" | cryptsetup open /dev/"$diskpart" $2
}

layoutnormalfn() 
{
    echo "Creating EFI partition."
    read -p "Enter size of EFI partition in MiB (Enter integer value): " efisize
    if [[ ! "$efisize" =~ ^-?[0-9]+$ ]]; then
        echo "Enter a integer only."
        layoutnormalfn
    elif [ "$efisize" -lt 32 ] ; then
        echo "Partition smaller than 32M, please make a bigger partition."
    else
        echo "Partition bigger than 32M using FAT32"
        sgdisk --new=1:0:+"$efisize"M --typecode=1:ef00 --change-name=1:"EFI" /dev/$SELECTED_DISK > /dev/null
        partprobe /dev/$SELECTED_DISK
    fi
        
    echo "Creating root partition."
    read -p "Enter size of root partition in GiB (Enter integer value or useleftover): " rootsize
    if [ $rootsize = "useleftover" ] ; then
        sgdisk --new=2:-0 --typecode=2:"$rootfscode" --change-name=2:"ROOT" /dev/$SELECTED_DISK > /dev/null
        partprobe /dev/$SELECTED_DISK
    elif [[ ! "$rootsize" =~ ^-?[0-9]+$ ]]; then
        echo "Enter a integer only."
        layoutnormalfn
    else
        sgdisk --new=2:0:+"$rootsize"G --typecode=2:"$rootfscode" --change-name=2:"ROOT" /dev/$SELECTED_DISK > /dev/null
        partprobe /dev/$SELECTED_DISK
    fi
}

layoutenchomefn() 
{
    echo "Creating EFI partition."
    read -p "Enter size of EFI partition in MiB (Enter integer value): " efisize
    if [[ ! "$efisize" =~ ^-?[0-9]+$ ]]; then
        echo "Enter a integer only."
        layoutenchomefn
    fi
    sgdisk --new=1:0:+"$efisize"M --typecode=1:ef00 --change-name=1:"EFI" /dev/$SELECTED_DISK > /dev/null
    partprobe /dev/$SELECTED_DISK

    echo "Creating root partition."
    read -p "Enter size of root partition in GiB, eg 50Gib (Enter integer value): " rootsize
    if [[ ! "$rootsize" =~ ^-?[0-9]+$ ]]; then
        echo "Enter a integer only."
        layoutenchomefn
    else
        sgdisk --new=2:0:+"$rootsize"G --typecode=2:"$rootfscode" --change-name=2:"ROOT" /dev/$SELECTED_DISK > /dev/null
        partprobe /dev/$SELECTED_DISK
    fi

    echo "Creating home partition."
    read -p "Enter size of home partition in GiB (Enter integer value or useleftover): " homesize
    if [ $homesize = "useleftover" ] ; then
        sgdisk --new=3:-0 --typecode=3:8302 --change-name=3:"HOME" /dev/$SELECTED_DISK > /dev/null
        partprobe /dev/$SELECTED_DISK
    elif [[ ! "$homesize" =~ ^-?[0-9]+$ ]]; then
        echo "Enter a integer only."
        layoutenchomefn
    else
        sgdisk --new=3:0:+"$homesize"G --typecode=3:8302 --change-name=3:"HOME" /dev/$SELECTED_DISK > /dev/null
        partprobe /dev/$SELECTED_DISK
    fi
}

partitiondiskfn() 
{
    if [ $disklayout = "normal" ] ; then
        formatwarningfn
        layoutnormalfn
        echo "Choose / filesystem."
        choosefsfn
        echo "Creating / fs."
        makefsfn 2 "$diskfs"
        echo "Creating EFI fs."
        makefsfn 1 "fat"
        mkdir -p /mnt/gentoo
        mountdiskfn 2 /mnt/gentoo
        mountdiskfn 1 /mnt/gentoo/boot
    elif [ $disklayout = "lvm" ] ; then
        #formatwarningfn
        echo "still need to be implemented"
        exit
    elif [ $disklayout = "encroothome" ] ; then
        #formatwarningfn
        echo "still need to be implemented"
        exit
    elif [ $disklayout = "enchome" ] ; then
        formatwarningfn
        layoutenchomefn
        echo "Enter / filesystem."
        choosefsfn
        rootfs=$diskfs
        echo "Enter luks options for /home."
        encryptdiskfn 2 3
        echo "Enter /home filesystem."
        choosefsfn
        homefs=$diskfs
        clear
        echo "Creating EFI fs."
        makefsfn 1 "fat"
        echo "Creating ROOT fs."
        makefsfn 2 "$rootfs"
        echo "Creating HOME fs."
        opencryptfn 3 home
        makefsfn 3 "$homefs" "home"
        mountdiskfn 2 /mnt/gentoo
        mountdiskfn 3 /mnt/gentoo/home home
        mountdiskfn 1 /mnt/gentoo/boot
    elif [ $disklayout = "fde" ] ; then
        #formatwarningfn
        echo "still need to be implemented"
        exit
    fi
}

#installing base system

stage3archivefn() 
{
    PS3="Select a Gentoo stage 3 archive: "
    options=("openrc" "systemd" "desktop-openrc" "desktop-systemd" "hardened-systemd" "hardened-openrc" "Open Documentation" "Exit" )
    select opt in "${options[@]}"
    do
        case $opt in
            "openrc") stage3archive="openrc"
            stage3flags="elogind -systemd "
            clear
            break;;

            "systemd") stage3archive="systemd"
            stage3flags="systemd -elogind "
            clear
            break;;

            "desktop-openrc") stage3archive="desktop-openrc"
            stage3flags="elogind -systemd "
            clear
            break;;

            "desktop-systemd") stage3archive="desktop-systemd"
            stage3flags="systemd -elogind "
            clear
            break;;
            
            "hardened-systemd") stage3archive="hardened-systemd"
            stage3flags="systemd hardened -elogind "
            clear
            break;;

            "hardened-openrc") stage3archive="hardened-openrc"
            stage3flags="elogind hardened -systemd "
            clear
            break;;

            "Open Documentation") clear
            links https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Stage#Choosing_a_stage_file
            stage3archivefn
            break;;

            "Exit") exit ;;
            *) echo "Wrong option please select again"; stage3archivefn;;
        esac
    done
    
    wgettemp=$(mktemp -d)
    wget --directory-prefix=$wgettemp "https://distfiles.gentoo.org/releases/$architecture/autobuilds/current-stage3-$architecture-$stage3archive/latest-stage3-$architecture-$stage3archive.txt"
    latestarchive=$(grep "stage3-$architecture-$stage3archive-.*\.tar\.xz" $wgettemp/latest-stage3-$architecture-$stage3archive.txt | awk '{print $1}')
    wget "https://distfiles.gentoo.org/releases/$architecture/autobuilds/current-stage3-$architecture-$stage3archive/$latestarchive"
    wget "https://distfiles.gentoo.org/releases/$architecture/autobuilds/current-stage3-$architecture-$stage3archive/$latestarchive.DIGESTS" --directory-prefix=$wgettemp
    clear
    echo "Checking checksum of stage3archive."
    sha512=$(cat $wgettemp/$latestarchive.DIGESTS | awk '/# SHA512 HASH/ && !found { getline; print; found=1 }' | awk '{print $1}')
    echo "$sha512 $latestarchive" > $wgettemp/sha512-$latestarchive.txt
    sha512sum -c $wgettemp/sha512-$latestarchive.txt
    if [ ! $? = 0 ] ; then
        echo "sha512sum signature on archive not valid."
        rm -rf $latestarchive
        exit 10
    fi 
    tar xpvf $latestarchive --xattrs-include='*.*' --numeric-owner
    rm $latestarchive
}

#user/system infomation
kernelfn()
{   
    PS3="Select a kernel to install: "
    options=("sys-kernel/gentoo-kernel" "sys-kernel/gentoo-kernel-bin" "sys-kernel/gentoo-sources" "Open Documentation" "Exit" )
    select opt in "${options[@]}"
    do
        case $opt in
            "sys-kernel/gentoo-kernel") kernel="gentoo-kernel"
            clear
            break;;

            "sys-kernel/gentoo-kernel-bin") kernel="gentoo-kernel-bin"
            clear
            break;;

            "sys-kernel/gentoo-sources") kernel="gentoo-sources"
            clear
            break;;

            "Open Documentation") clear
            links https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Stage#Choosing_a_stage_file
            stage3archivefn
            break;;

            "Exit") exit ;;
            *) echo "Wrong option please select again"; stage3archivefn;;
        esac
    done
}

firmwarefn() 
{
    
}

bootloaderfn()
{
    PS3="Select a bootloader to install: "
    options=("sys-boot/grub" "Exit" )
    select opt in "${options[@]}"
    do
        case $opt in
            "sys-boot/grub") kernel="grub"
            clear
            break;;

            "Open Documentation") clear
            bootloaderfn
            break;;

            "Exit") exit ;;
            *) echo "Wrong option please select again"; bootloaderfn;;
        esac
    done
}

usernamefn()
{   
    read -p "Enter username: " username
    if [ "$username" = *\ * ]; then
        echo "Dont use spaces in username, try again."
        usernamefn
    fi
}

hostnamefn()
{   
    read -p "Enter hostname: " hostname
    if [ "$hostname" = *\ * ]; then
        echo "Dont use spaces in hostname, try again."
        hostnamefn
    fi
}

passwordfn() 
{
    read -s -p "Enter password: " PASSWORD1
    echo -ne "\n"
    read -rs -p "Re-enter password: " PASSWORD2
    echo -ne "\n"
    if [ "$PASSWORD1" = "$PASSWORD2" ]; then
        echo "Continuing."
    else
        echo "Passwords do not match."
        passwordfn
    fi
}

distrocheck
chronyd -q
internetfn
clear

echo "A Gentoo linux installer script."
echo -e "Note: This is for people that at least know the basics of linux,\nif you know nothing please do your research before breaking something."
read -p "Press Enter to continue..."
clear

architecturefn
echo "Select disk to install to."
echo "Note: Double check which disk to install to, before DELETING ALL YOUR DATA on the wrong disk."
selectdiskfn
echo -e "Selected disk: $SELECTED_DISK\n"

echo "What disk layout do you wish to install."
disklayoutfn
echo -e "Selected layout: $disklayout\n"

echo "Starting to partition disk."
partitiondiskfn
cd /mnt/gentoo
clear

usernamefn
hostnamefn
passwordfn
stage3archivefn
kernelfn

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
genfstab -U /mnt/gentoo/ > /mnt/gentoo/etc/fstab

arch-chroot /mnt/gentoo /bin/bash <<EOF
emerge-webrsync
emerge --verbose app-portage/mirrorselect app-misc/resolve-march-native app-portage/cpuid2cpuflags

echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
echo "#GCC/CLANG flags
COMMON_FLAGS=\"-O2 -pipe $(resolve-march-native)\"
CFLAGS=\"\${COMMON_FLAGS}\"
CXXFLAGS=\"\${COMMON_FLAGS}\"
FCFLAGS=\"\${COMMON_FLAGS}\"
FFLAGS=\"\${COMMON_FLAGS}\"

#Rust flags
RUSTFLAGS=\"-C target-cpu=native -C opt-level=2\"

LC_MESSAGES=C.utf8
ACCEPT_LICENSE=\"* **\"
MAKEOPTS=\"-j$(nproc)\"
ACCEPT_KEYWORDS=\"$architecture\"
VIDEO_CARDS=\"\"
INPUT_DEVICES=\"synaptics libinput evdev\"
GRUB_PLATFORMS=\"efi-64\"
qemu_softmmu_targets=\"\"
qemu_user_targets=\"$qemu_user_targets\"
LLVM_TARGETS=\"$LLVM_TARGETS\"
USE=\"bash-completion udev policykit dbus -modemmanager $stage3flags\"" > /etc/portage/make.conf

mirrorselect -s10 >> /etc/portage/make.conf

mkdir -p /etc/portage/package.use/sys-kernel
echo "sys-kernel/linux-firmware deduplicate unknown-license" >> /etc/portage/package.use/sys-kernel/linux-firmware
mkdir -p /etc/portage/package.use/net-misc
echo "net-misc/networkmanager -bluetooth -ppp" >> /etc/portage/package.use/net-misc/networkmanager
mkdir -p /etc/portage/package.use/sys-boot
echo "sys-boot/grub mount truetype" >> /etc/portage/package.use/sys-boot/grub

emerge -v net-misc/networkmanager net-misc/openssh app-shells/bash-completion sys-block/io-scheduler-udev-rules sys-boot/grub 

echo $hostname > /etc/hostname
if echo "$stage3archive" | grep "openrc" ; then
    echo $timezone > /etc/timezone
    echo "sys-apps/openrc -netifrc" > /etc/portage/package.use/openrc
    emerge -v net-misc/chrony
    rc-update add chronyd default
elif echo "$stage3archive" | grep "systemd" ; then 
    ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
    systemctl enable systemd-timesyncd.service
fi 

EOF
