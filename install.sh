#!/bin/bash

# install.sh: installation of OGN receiver software

# first, set some variables
RemoteAdminUser="ogn-admin"
ExpandFilesystem="No"
# and remember where this script was started
RUNPATH=$(pwd)

# fail on errors, undefined variables and pipe errors
set -euo pipefail

# ------  Phase ONE: install OGN software and dependencies

# step 1: install prerequisites
# first, wait for internet connection
until ping -c1 -W2 1.1.1.1 &>/dev/null ; do  echo hoi; sleep 1; done
#  get the correct time
apt install -y ntpdate
until ntpdate pool.ntp.org &>/dev/null; do 
	echo "time not in sync"
	sleep 1
done
# write the date in the version file
sed -i "s/INSTALLDATE/$(date +%F)/" version 
# next, install required packages
apt update
apt install -y ntp libjpeg8 libconfig9 fftw3-dev procserv lynx telnet dos2unix

# step 2: populate the blacklist to prevent claiming of the USB stick by the kernel
cat >> /etc/modprobe.d/rtl-glidernet-blacklist.conf <<EOF
blacklist rtl2832
blacklist rtl2838
blacklist r820t
blacklist rtl2830
blacklist dvb_usb_rtl28xxu
EOF

# step 3: compile special rtlsdr driver for Bias Tee
TEMPDIR=$(mktemp -d)
cd $TEMPDIR
apt -y install git g++ gcc make cmake build-essential libconfig-dev libjpeg-dev libusb-1.0-0-dev
git clone https://github.com/rtlsdrblog/rtl-sdr-blog
cd rtl-sdr-blog
cp rtl-sdr.rules /etc/udev/rules.d/rtl-sdr.rules
mkdir build
cd build
cmake ../ -DINSTALL_UDEV_RULES=ON
make install
ldconfig

# get rid of the old libraries
apt -y remove --purge rtl-sdr
apt -y autoremove
cd $RUNPATH

# step 4: get OGN executables for Pi 3B+ and earlier, and for Pi$ and up 
# get arm binaries
mkdir /home/pi/arm
cd /home/pi/arm
curl -O http://download.glidernet.org/arm/rtlsdr-ogn-bin-ARM-latest.tgz
tar -xf rtlsdr-ogn-bin-ARM-latest.tgz --no-same-owner
cd rtlsdr-ogn
chown root ogn-rf ogn-decode gsm_scan
chmod a+s ogn-rf ogn-decode gsm_scan
# get GPU binaries
mkdir /home/pi/gpu
cd /home/pi/gpu
curl -O http://download.glidernet.org/rpi-gpu/rtlsdr-ogn-bin-RPI-GPU-latest.tgz
tar -xf rtlsdr-ogn-bin-RPI-GPU-latest.tgz --no-same-owner
cd rtlsdr-ogn
chown root ogn-rf ogn-decode gsm_scan
chmod a+s ogn-rf ogn-decode gsm_scan
# copy binaries to Pi user home
cp -r /home/pi/arm/* /home/pi/
chown pi:pi /home/pi/rtlsdr-ogn
cd /home/pi/rtlsdr-ogn
# note: remove the binaries, these are copied in by rtlsdr-ogn on service start
#       which will fail if root-owned non-writeable binaries are present 
rm -f gsm_scan ogn-rf ogn-decode
cd $RUNPATH

# step 5: prepare executables and node for GPU
# move custom files to pi home
cp OGN-receiver-config-manager2 rtlsdr-ogn /home/pi/rtlsdr-ogn/
sed -i "s/REMOTEADMINUSER/$RemoteAdminUser/g" /home/pi/rtlsdr-ogn/OGN-receiver-config-manager2
# configure ogn executables and GPU node file
cd /home/pi/rtlsdr-ogn
if [ ! -e gpu_dev ]; then mknod gpu_dev c 100 0; fi
chmod a+x OGN-receiver-config-manager2 rtlsdr-ogn
cd $RUNPATH

# step 6: get WW15MGH.DAC for conversion between the Height-above-Elipsoid to Height-above-Geoid thus above MSL
# Note: Temporarily disabled, the file has moved and this break the installation
# wget --no-check-certificate https://earth-info.nga.mil/GandG/wgs84/gravitymod/egm96/binary/WW15MGH.DAC
# Provisionally copy a static version 
cp WW15MGH.DAC /home/pi/rtlsdr-ogn

# step 7: move configuration file to FAT32 partition in /boot for editing in any OS
cp OGN-receiver.conf /boot
sed -i "s/REMOTEADMINUSER/$RemoteAdminUser/g" /boot/OGN-receiver.conf

# step 8: install service
cd /home/pi/rtlsdr-ogn
cp -v rtlsdr-ogn /etc/init.d/rtlsdr-ogn
sed -i 's/Template/\/etc\/ogn/g' rtlsdr-ogn.conf
cp -v rtlsdr-ogn.conf /etc/rtlsdr-ogn.conf
update-rc.d rtlsdr-ogn defaults
cd -
