#!/bin/bash

STATUSDIR="/var/bmount"
CONFIGDIR="/etc/bmount"

VERBOSE=false
FORCE=false
UNMOUNT=false
DRYRUN=false

ALLOWSU=true
ALLOWNONSU=false

# Parse command line options
OPTIND=1
while getopts "vfudh" opt; do
    case "$opt" in
    v)  
    	VERBOSE=true
    	;;
    f)
    	FORCE=true
    	;;
    u)
    	UNMOUNT=true
    	;;
    d)
    	DRYRUN=true
    	;;
    h)
    	echo "Usage: bmount [OPTION]... [VOLUME]"
    	echo "Mounts the specified volume, or unmounts with -u."
    	echo "Volume must correspond to a file in ${CONFIGDIR}/volumes/."
    	echo "See examples in ${CONFIGDIR}/volumes/examples/."
    	echo
    	echo "  -u  unmount the volume"
    	echo "  -f  force. some warnings can be ignored with this."
    	echo "  -d  dry run"
    	echo "  -v  verbose"
    	echo "  -h  this message"
    	echo
    	echo "Mount a volume:"
    	echo "	bmount volume1"
    	echo "Unmount a volume:"
    	echo "	bmount -u volume1"
    	echo "Force mount after an expected shutdown:"
    	echo "	bmount -f volume1"
    	echo "Dry run to check a volume's config file:"
    	echo "	bmount -dv volume1"
    	exit 0
    	;;
    esac
done
shift $((OPTIND-1))
[ "$1" = "--" ] && shift

# The volume should be specified after the options
[[ $1 ]] && VOLUME=$1

if [[ ! $VOLUME ]]; then
	echo "A volume to mount must be specified."
	exit 1
fi

# Load volume file
VOLUMEFILE="${CONFIGDIR}/volumes/${VOLUME}"
if [ ! -f ${VOLUMEFILE} ]; then
	echo "Config file ${VOLUMEFILE} doesn't exist."
	exit 1
fi
source ${VOLUMEFILE}


# Enforce ALLOWSU setting
if ! $ALLOWSU && [[ $UID -eq 0 ]]; then
	echo "Please run this script as a regular user (non-root)."
	exit 1
fi

# Enforce ALLOWNONSU setting
if ! $ALLOWNONSU && [[ $UID != 0 ]]; then
	echo "Please run this script as the superuser:"
	echo "sudo $0 $*"
	exit 1
fi


# Mount command mode
if [[ $MOUNTCMD ]] && [[ $UMOUNTCMD ]]; then
	if $DRYRUN; then
		echo "This is a dry-run. Operations that would have been run:"
	
		! $UNMOUNT && echo "Mount command: ${MOUNTCMD}"
		$UNMOUNT && echo "Unmount command: ${UMOUNTCMD}"
		
		exit 0		
	fi
	
	if ! $UNMOUNT; then
		$MOUNTCMD
	else
		$UMOUNTCMD
	fi
	
	exit 0
fi


# Validate volume file
if [[ $RAWDEV ]] && [[ $LOOPBACKFILE ]]; then
	echo "RAWDEV and LOOPBACKFILE can't be set for the same volume."
	exit 1
fi

if [[ ! $RAWDEV ]] && [[ ! $LOOPBACKFILE ]]; then
	echo "RAWDEV or LOOPBACKFILE must be set for this volume."
	exit 1
fi

if [[ ! $MOUNT ]]; then
	echo "MOUNT not set for this volume."
	exit 1
fi

[[ $RAWDEV ]] && LASTDEST=$RAWDEV

LOOP=false
if [[ $LOOPBACKFILE ]]; then
	LOOP=true
	LOOPSRC=$LOOPBACKFILE
	if $UNMOUNT; then
		if [ ! -f "${STATUSDIR}/loopback/${VOLUME}" ]; then
			echo "Can't figure out which loopback device to unmount."
			! $FORCE && exit 1
			echo "Forced: will not try to unmount loopback device."
			LOOP=false
		else
			LOOPDEST=$(cat "${STATUSDIR}/loopback/${VOLUME}")
		fi
	else
		if [ -f "${STATUSDIR}/loopback/${VOLUME}" ]; then
			echo "${VOLUME} may already be mounted."
			! $FORCE && exit 1
		fi
		if ! LOOPDEST=$(sudo losetup -f 2> /dev/null); then
			echo "Could not find an unused loopback device."
			exit 1
		fi
	fi
	LASTDEST=$LOOPDEST
fi

CRYPT=false
if [[ $CRYPTDEV ]]; then
	CRYPT=true
	CRYPTSRC=$LASTDEST
	CRYPTDEST=$CRYPTDEV
	LASTDEST=/dev/mapper/$CRYPTDEST
fi

MOUNTSRC=$LASTDEST
MOUNTDEST=$MOUNT

if $DRYRUN; then
	echo "This is a dry-run. Operations that would have been run:"
	
	$LOOP && echo "Loop from ${LOOPSRC}"
	$LOOP && echo "Loop to ${LOOPDEST}"

	$CRYPT && echo "Crypt from ${CRYPTSRC}"
	$CRYPT && echo "Crypt to ${CRYPTDEST}"

	echo "Mount from ${MOUNTSRC}"
	echo "Mount to ${MOUNTDEST}"
	
	exit 0
fi

# Mount operations
if ! $UNMOUNT; then

	if $LOOP; then
		losetup ${LOOPDEST} ${LOOPSRC}
	
		echo ${LOOPDEST} > ${STATUSDIR}/loopback/${VOLUME}
	
		$VERBOSE && echo "Loopback setup for ${LOOPSRC} on ${LOOPDEST}."
	fi

	# Open LUKS container if requested
	if $CRYPT; then
		cryptsetup luksOpen "$CRYPTSRC" "$CRYPTDEST"
	
		$VERBOSE && echo "LUKS container ${CRYPTSRC} opened as /dev/mapper/${CRYPTDEST}."
	fi

	# Mount the volume
	mount ${MOUNTSRC} ${MOUNTDEST}

	$VERBOSE && echo "Device ${MOUNTSRC} mounted to ${MOUNTDEST}."
	
# Unmount operations
else
	# Unmount the volume
	umount "${MOUNTDEST}"
	
	$VERBOSE && echo "Device ${MOUNTSRC} unmounted from ${MOUNTDEST}."
	
	# Close LUKS container if requested
	if $CRYPT; then
		cryptsetup luksClose "$CRYPTDEST"
		
		$VERBOSE && echo "LUKS container ${CRYPTDEST} closed."
	fi
	
	# Unloop if requested
	if $LOOP; then
		losetup -d "$LOOPDEST"
		rm "${STATUSDIR}/loopback/${VOLUME}"
		
		$VERBOSE && echo "Loopback device ${LOOPDEST} closed."
	fi
fi

# End of file
