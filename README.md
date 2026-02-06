# LAN9662 Rootfs Update Script

## Update Methods

## Quick Start

This script performs a safe A/B rootfs update for the LAN9662 SoC:

### Prerequisites:
- Running SSH Dropbear server on the target device
- Root user with password authentication enabled
- The script prog.sh handles it all. Either it is already available on the target, or it has to be copied to the target

### Method 1: Direct UART Console (TeraTerm)

For direct console access without network setup:

1. **Prepare data partition:**
- if the programming script isn't already available, then copy from host (Windows) to target (LAN9662) with:
- ```scp -O prog.sh root@169.254.45.100:/sbin```
- in the target console ensure execution rights with
- ```chmod 744 /sbin/prog.sh ```
- and execute script with 
- ```/sbin/prog.sh```
- The script will format `/dev/mmcblk0p7` and mount it to `/data`.
- Transfer `brsdk_standalone_arm.ext4.gz` to `/data/` using these method:
- ```scp -O brsdk_standalone_arm.ext4.gz root@169.254.45.100:/data/```
- Press ENTER in the script to continue with the update process
- The script will extract and install the image automatically

### Method 2: SSH Remote Access

For network-based remote update:


### Usage:
1. **Copy script to target system:**
   ```bash
   scp -O prog.sh root@<TARGET_IP>:/sbin/
   ssh root@<TARGET_IP> "chmod 744 /sbin/prog.sh"
   ```
2. **Prepare image:**
   Have `brsdk_standalone_arm.ext4.gz` ready on your host computer.

3. **Run the script:**
   ```bash
   ssh root@<TARGET_IP> "/sbin/prog.sh"
   ```

4. **Follow instructions:**
   The script will guide you through the SCP upload process and perform the update automatically.

**Important:** Root privileges required, active network connection to target device necessary.

## Overview

The `prog.sh` script is a comprehensive rootfs update utility designed for the LAN9662 System-on-Chip (SoC). It implements a safe A/B partition update mechanism that allows for reliable firmware updates without the risk of bricking the device.

## Features

- **Redundant Boot System**: Uses A/B partitioning (mmcblk0p5/p6) for safe updates
- **Automatic Slot Detection**: Intelligently determines active and inactive boot slots
- **Data Partition Management**: Automatically prepares `/dev/mmcblk0p7` for image storage
- **Network Transfer Support**: Provides SCP commands for easy image transfer
- **U-Boot Environment Control**: Automatically configures boot parameters in SPI flash
- **Error Handling**: Comprehensive error checking and validation throughout the process

## System Requirements

### Hardware
- **SoC**: LAN9662 (Microchip)
- **Storage**: eMMC/MMC with specific partition layout:
  - `/dev/mmcblk0p5`: Root partition A
  - `/dev/mmcblk0p6`: Root partition B  
  - `/dev/mmcblk0p7`: Data partition
- **Flash**: SPI flash for U-Boot environment storage
- **Network**: Ethernet interface (eth0) for file transfer

### Software
- **Linux**: Embedded Linux with U-Boot bootloader
- **Tools Required**:
  - `fw_setenv/fw_printenv` (U-Boot environment tools)
  - `mkfs.ext4` (filesystem utilities)
  - `dd`, `gunzip`, `mount/umount`
  - `scp` (for file transfer)

## Installation

### Deploying the Script to Target

1. **Copy script to target system**:
   ```bash
   scp -O prog.sh root@<TARGET_IP>:/sbin/
   ```

2. **Make executable**:
   ```bash
   chmod 744 /sbin/prog.sh
   ```

3. **Run the script**:
   ```bash
   /sbin/prog.sh
   ```

## Usage

### Prerequisites

1. **Root Access**: Script must be run with root privileges
2. **Image File**: Prepare `brsdk_standalone_arm.ext4.gz` on host computer
3. **Network Connectivity**: Ensure target board is accessible via SSH/SCP

### Step-by-Step Process

#### Step 1: Data Partition Preparation
- Formats `/dev/mmcblk0p7` as ext4
- Creates mount point `/data` if not exists
- Mounts the data partition for image storage

#### Step 2: Image Transfer
- Detects target IP address automatically
- Provides SCP command for host computer:
  ```bash
  scp -O brsdk_standalone_arm.ext4.gz root@<TARGET_IP>:/data/
  ```
- Includes troubleshooting for SSH key conflicts

#### Step 3: Image Extraction
- Decompresses `.gz` file using `gunzip`
- Validates extracted image file

#### Step 4: Boot Slot Detection
- Analyzes `/proc/cmdline` to determine current root partition
- Identifies active slot (5 or 6)
- Selects inactive slot for update

#### Step 5: Image Installation
- Unmounts target partition if mounted
- Writes image to inactive slot using `dd` with optimized parameters
- Uses `bs=1M conv=fsync` for reliable writing

#### Step 6: U-Boot Configuration
Creates `/etc/fw_env.config` with SPI flash parameters:
```
/dev/mtd0       0x00180000     0x00040000  0x00001000
/dev/mtd0       0x001C0000     0x00040000  0x00001000
```

#### Step 7: Automatic Boot Configuration
- Sets `mmc_cur` to new boot slot
- Sets `mmc_bak` to current slot (for fallback)
- Updates U-Boot environment in SPI flash

## U-Boot Environment Details

### SPI Flash Layout
- **Primary Environment**: Offset 0x180000 (1.5MB)
- **Redundant Environment**: Offset 0x1C0000 (1.75MB)
- **Size**: 256KB each (0x40000)
- **Sector Size**: 4KB (0x1000)

### Boot Variables
- **mmc_cur**: Current active boot slot (5 or 6)
- **mmc_bak**: Backup slot for fallback mechanism

## Safety Features

### Redundant Boot System
- **A/B Updates**: Never overwrites currently running system
- **Fallback Mechanism**: U-Boot can revert to previous slot on boot failure
- **Dual Environment**: Redundant U-Boot environments prevent corruption

### Error Prevention
- **Root Privilege Check**: Prevents accidental execution
- **Partition Validation**: Verifies expected partition layout
- **Mount State Checking**: Safely handles mounted partitions
- **File Existence Validation**: Confirms image files before processing

## Troubleshooting

### Common Issues

#### SSH Key Conflicts
If you see "REMOTE HOST IDENTIFICATION HAS CHANGED":
```bash
ssh-keygen -R <TARGET_IP>
```

#### Permission Issues
Ensure script runs as root:
```bash
sudo /sbin/prog.sh
```

#### Partition Issues
Verify partition layout:
```bash
fdisk -l /dev/mmcblk0
```

#### U-Boot Environment Issues
Check environment access:
```bash
fw_printenv
```

### Manual U-Boot Configuration

If automatic configuration fails, manually set in U-Boot:

For slot 5:
```
U-Boot> setenv mmc_cur 5
U-Boot> setenv mmc_bak 6
U-Boot> saveenv
U-Boot> boot
```

For slot 6:
```
U-Boot> setenv mmc_cur 6
U-Boot> setenv mmc_bak 5
U-Boot> saveenv
U-Boot> boot
```

## File Structure

```
/dev/mmcblk0p5    # Root partition A
/dev/mmcblk0p6    # Root partition B
/dev/mmcblk0p7    # Data partition (/data)
/dev/mtd0         # SPI flash (U-Boot environment)
/etc/fw_env.config # U-Boot tools configuration
```

## Storage Layout

### eMMC Partition Layout

The LAN9662 system uses a carefully designed eMMC partition layout to support redundant booting and reliable firmware updates:

```
+-------------------+----------------+--------------------+---------------------------------------------+
| Device            | Start Sector   | Start Address (hex)| Purpose                                     |
+-------------------+----------------+--------------------+---------------------------------------------+
| /dev/mmcblk0      | 0              | 0x00000000         | Complete eMMC device                        |
| /dev/mmcblk0p1    | 64             | 0x00008000         | Firmware Image Package, Bootloader Code     |
| /dev/mmcblk0p2    | 262208         | 0x08008000         | Backup FIP Partition                        |
| /dev/mmcblk0p3    | 524352         | 0x10008000         | U-Boot Environment                          |
| /dev/mmcblk0p4    | 528448         | 0x10208000         | Backup Environment                          |
| /dev/mmcblk0p5    | 532544         | 0x10408000         | Boot Slot A (Kernel+Rootfs Image)          |
| /dev/mmcblk0p6    | 2629696        | 0xA0408000         | Boot Slot B (Kernel+Rootfs Image, current) |
| /dev/mmcblk0p7    | 4726848        | 0x120408000        | Data/Persistence Partition                  |
+-------------------+----------------+--------------------+---------------------------------------------+
```

**Key Partitions:**
- **p1/p2**: Redundant bootloader storage (FIP - Firmware Image Package)
- **p3/p4**: Redundant U-Boot environments (also mirrored in SPI flash)
- **p5/p6**: A/B root filesystem slots for safe updates
- **p7**: User data partition, used by update script for temporary storage

### SPI Flash Layout

The SPI flash contains critical boot components and configuration:

```
+-------------------+-----------+----------+---------------------------------------------+
| Device            | Size      | GPT Name | Purpose                                     |
+-------------------+-----------+----------+---------------------------------------------+
| /dev/mtd0         | 2.0 MB    | spi1     | Complete SPI Flash                          |
| /dev/mtd0_fip     | 1.5 MB    | fip      | Firmware Image Package, Bootloader Code     |
| /dev/mtd0_env     | 256 kB    | Env      | U-Boot Environment (primary copy)           |
| /dev/mtd0_envbk   | 256 kB    | Env.bak  | Backup Environment (redundant copy)         |
+-------------------+-----------+----------+---------------------------------------------+
```

### SPI Flash Memory Map

```
Address (hex)      Size        Region       Content / Purpose
──────────────────────────────────────────────────────────────────────────────
0x00000000
    │
    │   0x00180000 (1,536 KiB)
    │
    ├─────────────────────────────── FIP (Firmware Image Package)
    │                               - U-Boot SPL / TF-A / additional FW
    │                               - Boot code that starts the CPU
0x00180000
    │
    │   0x00040000 (256 KiB)
    │
    ├─────────────────────────────── Env (Primary Environment)
    │                               - U-Boot variables as Key=Value pairs:
    │                                 e.g., mmc_cur, mmc_bak, bootcmd,
    │                                 bootargs, mtdparts, offsets etc.
    │                               - CRC / Management data
0x001C0000
    │
    │   0x00040000 (256 KiB)
    │
    ├─────────────────────────────── Env.bak (Backup Environment)
    │                               - Redundant copy of environment
    │                               - Used if primary Env is corrupted
0x00200000 (End, 2 MiB)
```

**Important Notes:**
- **Redundancy**: Both eMMC and SPI flash contain U-Boot environments for maximum reliability
- **Boot Order**: System boots from SPI flash (FIP), then loads kernel/rootfs from eMMC
- **Update Safety**: A/B partitioning (p5/p6) ensures system never becomes unbootable
- **Environment Access**: Script uses `/etc/fw_env.config` to access SPI flash environments

## Recovery Procedures

### Boot Failure Recovery
1. **Access U-Boot**: Interrupt boot process (spacebar)
2. **Check Environment**: `printenv`
3. **Switch Slots**: Manually set `mmc_cur` and `mmc_bak`
4. **Save and Boot**: `saveenv` then `boot`

### Complete Recovery
If both slots are corrupted:
1. Boot from external media (SD card, USB)
2. Re-flash both partitions manually
3. Restore U-Boot environment

## Development Notes

### Script Customization
- Modify partition paths in variables section
- Adjust SPI flash offsets if hardware differs
- Customize network interface detection

### Image Requirements
- **Format**: ext4 filesystem image
- **Compression**: gzip (.gz)
- **Naming**: `brsdk_standalone_arm.ext4.gz`

## Security Considerations

- **Root Access**: Script requires and validates root privileges
- **Network Security**: Uses SCP with authentication
- **Flash Protection**: Redundant environments prevent brick scenarios
- **Validation**: Multiple checkpoints prevent partial updates

## Version History

- **Initial Version**: Basic A/B update functionality
- **Current**: Enhanced error handling, automatic U-Boot configuration

## Support

For issues specific to LAN9662 hardware or U-Boot configuration, consult:
- LAN9662 Hardware Reference Manual
- Microchip U-Boot Documentation
- Embedded Linux Build System Documentation

---

**Note**: This script is specifically designed for LAN9662 SoC systems with the described partition layout. Modification may be required for different hardware configurations.