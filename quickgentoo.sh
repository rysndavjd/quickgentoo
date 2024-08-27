#!/bin/bash

version=0.1
PASSWORD=""
ROOTPASSWORD=""

if [ "$(id -u)" != 0 ] ; then 
    echo "Run as root."
    exit 1
fi

help() {
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
internetfn(){
    echo "Checking internet access by sending a ping to Cloudflare (1.1.1.1)."
    if ping -c 1 1.1.1.1 &> /dev/null ; then
        echo "Internet access is available."
    else
        echo "No internet access, checking rfkill."
        if rfkill list wifi | grep -q "Hard blocked: yes" ; then
            echo "Wifi is hard blocked (Blocked via hardware switch.)"
            exit 1
        elif rfkill list wifi | grep -q "Soft blocked: yes" ; then
            echo "Wifi is soft blocked, overriding (Blocked via software.)"
            rfkill unblock wifi
            echo "Connect to wifi via "
        fi
        
    fi
    sleep 1
}

architecturefn() {
    PS3="Select architecture to install for: "
    options=("amd64" "x86" "arm64" "riscv" "Open Documentation" "Exit" )
    select opt in "${options[@]}"
    do
        case $opt in
            "amd64") architecture="openrc"
            clear
            echo "Architecture chosen $architecture."
            break;;

            "x86") architecture="systemd"
            clear
            echo "Architecture chosen $architecture."
            break;;

            "arm64") architecture="riscv"
            clear
            echo "Architecture chosen $architecture."
            break;;

            "riscv") architecture="systemd"
            clear
            echo "Architecture chosen $architecture."
            break;;

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

getstage3archivefn() {
    PS3="Select a Gentoo stage 3 archive: "
    options=("openrc" "systemd" "desktop-openrc" "desktop-systemd" "hardened-systemd" "hardened-openrc" "Open Documentation" "Exit" )
    select opt in "${options[@]}"
    do
        case $opt in
            "openrc") stage3archive="openrc"
            clear
            echo "Stage3 chosen $stage3archive."
            break;;

            "systemd") stage3archive="systemd"
            clear
            echo "Stage3 chosen $stage3archive."
            break;;

            "desktop-openrc") stage3archive="desktop-openrc"
            clear
            echo "Stage3 chosen $stage3archive."
            break;;

            "desktop-systemd") stage3archive="desktop-systemd"
            clear
            echo "Stage3 chosen $stage3archive."
            break;;
            
            "hardened-systemd") stage3archive="hardened-systemd"
            clear
            echo "Stage3 chosen $stage3archive."
            break;;

            "hardened-openrc") stage3archive="hardened-openrc"
            clear
            echo "Stage3 chosen $stage3archive."
            break;;

            "Open Documentation") clear
            links https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Stage#Choosing_a_stage_file
            getstage3archivefn
            break;;

            "Exit") exit ;;
            *) echo "Wrong option please select again"; getstage3archivefn;;
        esac
    done
    
    wgettemp=$(mktemp -d)
    wget --directory-prefix=$wgettemp "https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-$stage3archive/latest-stage3-amd64-$stage3archive.txt"
    latestarchive=$(grep "stage3-amd64-$stage3archive-.*\.tar\.xz" $wgettemp/latest-stage3-amd64-$stage3archive.txt | awk '{print $1}')
    wget "https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-$stage3archive/$latestarchive"
}


#partitioning 

#fn (DISK use)
selectdiskfn() {
    listblk=$(lsblk -d -n -o NAME)
    PS3="Please select a disk: "
    options=()
    names=()

    while read -r line ; do
        NAME=$(echo "$line")
        options+=("$NAME")
    done <<< "$listblk"

    select opt in "${options[@]}"; do
        if [[ -n "$opt" ]]; then
            SELECTED_DISK=$opt
            break
        else
            echo "Invalid selection. Please choose a valid number."
        fi
    done
}

checkpartitionfn() {
    blkraw=$(blkid /dev/$1* --output device)
    blksort=$(echo $blkraw | sed "s/\/dev\/$1//")
    #for listpart in $blksort ; do
    #    echo $listpart
    #done
}

disklayoutfn() {
    PS3="Please select a layout: "
    options=("Normal" "LVM" "Encrypted Root+Home" "Encrypted Home" "Full Disk Encryption" "Open Documentation" "Exit")
    select opt in "${options[@]}"
    do
        case $opt in
            "Normal") disklayout="normal"
            clear
            echo "Layout chosen normal."
            break;;

            "LVM") disklayout="lvm"
            clear
            echo "Layout chosen LVM."
            break;;

            "Encrypted Root+Home") disklayout="encroothome"
            clear
            echo "Layout chosen Encrypted Root+Home."
            break;;

            "Encrypted Home") disklayout="enchome"
            clear
            echo "Layout chosen Encrypted Home."
            break;;
            
            "Full Disk Encryption") disklayout="fde"
            clear
            echo "Layout chosen Full Disk Encryption."
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

partitiondiskfn() {
    if [ $disklayout = "normal" ] ; then
        pass
    elif [ $disklayout = "lvm" ] ; then
        pass
    elif [ $disklayout = "encroothome" ] ; then
        pass
    elif [ $disklayout = "enchome" ] ; then
        pass
    elif [ $disklayout = "fde" ] ; then
        pass
    fi


}

#user infomation
usernamefn()
{   
    read -p "Enter username: " USERNAME
}

#fn (USER)
passwordfn() 
{
    read -sp "Enter password for $1: " PASSWORD
}



echo "A Gentoo linux installer script."
echo -e "Note: This is for people that at least know the basics of linux,\nif you know nothing please do your research before breaking something."
read -p "Press Enter to continue..."
clear

internetfn
clear

echo "Select disk to install to."
selectdiskfn

echo "What disk layout do you wish to install."
disklayoutfn

