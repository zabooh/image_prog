#!/bin/sh
#
# update_rootfs.sh
#
# Deployment Instructions:
#  - Copy script to target: scp -O prog.sh root@IP_ADDRESS:/sbin/
#  - Make executable: chmod 744 /sbin/prog.sh
#  - Run on target: /sbin/prog.sh
#
# Process:
#  1) Always format /dev/mmcblk0p7 as ext4 and mount to /data
#  2) User: Copy image via scp to /data
#  3) Extract image (/data/brsdk_standalone_arm.ext4.gz -> .ext4)
#  4) Determine active root slot (p5 or p6)
#  5) Write image to INACTIVE slot
#  6) Set U-Boot-Env (mmc_cur/mmc_bak) to new slot

set -e

IMAGE_GZ="/data/brsdk_standalone_arm.ext4.gz"
IMAGE="/data/brsdk_standalone_arm.ext4"
DATA_DEV="/dev/mmcblk0p7"
DATA_MNT="/data"

echo "== Rootfs Update Script with /data Preparation =="

# 1. Check if we are running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Please run as root."
    exit 1
fi

########################################
# Step 1: Prepare data partition
########################################
echo "== Step 1: Prepare data partition =="

# Ensure mountpoint exists
if [ ! -d "$DATA_MNT" ]; then
    echo "Mountpoint $DATA_MNT does not exist, creating it."
    mkdir -p "$DATA_MNT"
fi

# If already mounted, unmount (we want to format)
if mount | grep -q "$DATA_DEV"; then
    echo "WARNING: $DATA_DEV is mounted, unmounting..."
    umount "$DATA_DEV"
fi

echo "Formatting $DATA_DEV as ext4..."
echo "WARNING: All data on $DATA_DEV will be deleted!"
mkfs.ext4 -F "$DATA_DEV"

echo "Mounting $DATA_DEV to $DATA_MNT..."
mount "$DATA_DEV" "$DATA_MNT"

echo "Data partition is ready:"
df -h "$DATA_MNT"

########################################
# Step 2: Copy image via SCP
########################################
echo
echo "== Step 2: Copy image via SCP to target =="

# Determine IP address of eth0
ETH0_IP=$(ip addr show eth0 | grep 'inet ' | grep -v 'inet6' | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1)

if [ -z "$ETH0_IP" ]; then
    echo "WARNING: Could not determine IP address of eth0."
    echo "Please run the following command on the host computer (e.g. Windows CMD):"
    echo
    echo "  scp -O brsdk_standalone_arm.ext4.gz root@<IP_OF_BOARD>:$DATA_MNT/"
    echo
    echo "Replace <IP_OF_BOARD> with the correct IP address of the LAN9662 board."
else
    echo "Detected IP address of eth0: $ETH0_IP"
    echo
    echo "Please run the following command on the host computer (e.g. Windows CMD):"
    echo
    echo "  scp -O brsdk_standalone_arm.ext4.gz root@${ETH0_IP}:$DATA_MNT/"
    echo
    echo "if the Waring REMOTE HOST IDENTIFICATION HAS CHANGED appears, you may need to remove the old key from your known_hosts file"
    echo "  ssh-keygen -R $ETH0_IP"
    echo "and then repeat scp command"
fi
echo "When the copy process is complete, press ENTER here."
read _dummy

# Check if .gz file exists
if [ ! -f "$IMAGE_GZ" ] && [ ! -f "$IMAGE" ]; then
    echo "ERROR: Neither $IMAGE_GZ nor $IMAGE found."
    echo "Make sure you copied the file brsdk_standalone_arm.ext4.gz to $DATA_MNT."
    exit 1
fi

########################################
# Step 3: Extract image
########################################
echo
echo "== Step 3: Extract image =="

if [ -f "$IMAGE_GZ" ]; then
    echo "Extracting $IMAGE_GZ..."
    gunzip -f "$IMAGE_GZ"
fi

if [ ! -f "$IMAGE" ]; then
    echo "ERROR: Extracted image $IMAGE not found."
    exit 1
fi

echo "Image found:"
ls -lh "$IMAGE"

########################################
# Step 4: Determine inactive boot slot
########################################
echo
echo "== Step 4: Determine inactive boot slot =="

ROOTDEV="$(sed -n 's/.*root=\([^ ]*\).*/\1/p' /proc/cmdline)"

if [ -z "$ROOTDEV" ]; then
    echo "ERROR: Could not find root= in /proc/cmdline."
    exit 1
fi

echo "Current root device according to /proc/cmdline: $ROOTDEV"

case "$ROOTDEV" in
    /dev/mmcblk0p5)
        ACTIVE_SLOT=5
        INACTIVE_SLOT=6
        ;;
    /dev/mmcblk0p6)
        ACTIVE_SLOT=6
        INACTIVE_SLOT=5
        ;;
    *)
        echo "ERROR: Unexpected root device: $ROOTDEV"
        echo "This script only supports /dev/mmcblk0p5 or /dev/mmcblk0p6 as root."
        exit 1
        ;;
esac

echo "Active boot slot    : mmcblk0p${ACTIVE_SLOT}"
echo "Inactive boot slot  : mmcblk0p${INACTIVE_SLOT}"

TARGET_DEV="/dev/mmcblk0p${INACTIVE_SLOT}"

# Make sure target slot is not mounted
if mount | grep -q "$TARGET_DEV"; then
    echo "Target partition $TARGET_DEV is mounted, trying to unmount..."
    umount "$TARGET_DEV" || {
        echo "ERROR: Could not unmount $TARGET_DEV."
        exit 1
    }
fi

########################################
# Step 5: Write image to inactive slot
########################################
echo
echo "== Step 5: Write image to $TARGET_DEV =="
echo "This may take some time..."

dd if="$IMAGE" of="$TARGET_DEV" bs=1M conv=fsync

echo "Image has been written to $TARGET_DEV."


########################################
# Step 6: U-Boot instructions
########################################
echo
echo "== Step 6: U-Boot instructions =="

echo "The rootfs image has been written to the inactive slot:"
echo "  New slot: /dev/mmcblk0p${INACTIVE_SLOT}"
echo
echo "To boot from this slot on next boot, please:"
echo
echo "1) Restart the board and stop U-Boot (e.g. with spacebar)."
echo "2) Enter the following commands at the U-Boot prompt:"
echo

if [ "$INACTIVE_SLOT" -eq 5 ]; then
    echo "  U-Boot> setenv mmc_cur 5"
    echo "  U-Boot> setenv mmc_bak 6"
else
    echo "  U-Boot> setenv mmc_cur 6"
    echo "  U-Boot> setenv mmc_bak 5"
fi

########################################
# Step 7: Create fw_env.config
########################################
echo
echo "== Step 7: Create /etc/fw_env.config =="
echo
echo "The file /etc/fw_env.config configures the U-Boot environment tools (fw_setenv/fw_printenv)"
echo "for accessing the U-Boot environment in SPI flash."
echo
echo "Parameter explanation:"
echo "  /dev/mtd0       = MTD device (SPI Flash)"
echo "  0x00180000     = Primary environment offset (1.5MB)"
echo "  0x001C0000     = Redundant environment offset (1.75MB)" 
echo "  0x00040000     = Environment size (256KB)"
echo "  0x00001000     = Sector size (4KB)"
echo
echo "The LAN9662 system uses redundant U-Boot environments for fail-safety."
echo "Both areas contain the same boot parameters (mmc_cur, mmc_bak, etc.)"
echo

cat > /etc/fw_env.config << 'EOF'
/dev/mtd0       0x00180000     0x00040000  0x00001000
/dev/mtd0       0x001C0000     0x00040000  0x00001000
EOF

echo "File /etc/fw_env.config has been created:"
cat /etc/fw_env.config
echo
echo "This configuration enables the fw_setenv/fw_printenv tools"
echo "to read and write U-Boot variables directly from Linux."

########################################
# Step 8: Set U-Boot environment automatically
########################################
echo
echo "== Step 8: Set U-Boot environment in SPI flash =="

echo "Setting boot slots in U-Boot environment:"
if [ "$INACTIVE_SLOT" -eq 5 ]; then
    echo "  fw_setenv mmc_cur 5"
    echo "  fw_setenv mmc_bak 6"
    fw_setenv mmc_cur 5
    fw_setenv mmc_bak 6
else
    echo "  fw_setenv mmc_cur 6"
    echo "  fw_setenv mmc_bak 5"
    fw_setenv mmc_cur 6
    fw_setenv mmc_bak 5
fi

echo "U-Boot environment has been set automatically."
echo "Next boot will start from slot ${INACTIVE_SLOT}."


if [ "$INACTIVE_SLOT" -eq 5 ]; then
    echo "  U-Boot> setenv mmc_cur 5"
    echo "  U-Boot> setenv mmc_bak 6"
else
    echo "  U-Boot> setenv mmc_cur 6"
    echo "  U-Boot> setenv mmc_bak 5"
fi

echo "  U-Boot> saveenv"
echo "  U-Boot> boot"
echo
echo "Explanation:"
echo "  mmc_cur = active boot slot (rootfs partition)"
echo "  mmc_bak = backup slot for fallback"
echo
echo "== Finished. The system is ready for restart with the new image. =="
