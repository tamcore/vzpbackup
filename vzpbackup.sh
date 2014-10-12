#!/bin/bash

# DEFAULTS
DESTINATION="/vz/backup"
KEEP_COUNT=0
SUSPEND="no"
FULL_BACKUP="no"
INC_BACKUP="no"
VZCTL_PARAM=""
BACKUP_VES=""
RSYNC_SRCS=""

# COMMANDLINE PARSING
shopt -s extglob
for param in "$@"; do
  case $param in
    -h|--help)
      echo "Usage: $0 [--destination=<backup-destination>] [--keep-count=<keep count>] [--suspend=<yes|no>] <--full or --inc(cremental)> <--all or VEIDs>"
      echo "Defaults:"
      echo "- --destination=$DESTINATION"
      echo "- --keep-count=$KEEP_COUNT"
      echo "- --suspend=$SUSPEND"
      exit 0
    ;;
    --destination=*)
      DESTINATION=${param#*=}
    ;;
    --keep-count=+([0-9]))
      KEEP_COUNT=${param#*=}
    ;;
    --suspend=+(yes|no))
      SUSPEND=${param#*=}
      test "$SUSPEND" = "yes" || VZCTL_PARAM="$VZCTL_PARAM --skip-suspend"
    ;;
    --full)
      FULL_BACKUP="yes"
    ;;
    --inc|--incremental)
      INC_BACKUP="yes"
    ;;
    --all)
      for VEID in $( vzlist -H -o ctid ); do
        BACKUP_VES="$BACKUP_VES $VEID"
      done
    ;;
    +([0-9]))
      BACKUP_VES="$BACKUP_VES $param"
    ;;
  esac
done
shopt -u extglob

# CHECKS
if [ "$BACKUP_VES" = "" ]; then
  echo "Neither --all or VEIDs is/are given.."
  exit 1
fi

if [ "$INC_BACKUP" = "no" ] && [ "$FULL_BACKUP" = "no" ]; then
  echo "Neither --inc(remental) or --full given.."
  exit 1
fi

if ! which vzctl &>/dev/null; then
  echo "Couldn't find vzctl in \$PATH. Are you sure it's there?"
  exit 1
fi

# LOCKFILE
test -f /var/run/vzbackup.pid && exit 0
touch /var/run/vzbackup.pid
trap "rm /var/run/vzbackup.pid" EXIT

# SCRIPT
for VEID in $BACKUP_VES; do
  if [ -d "/vz/private/$VEID" ]; then
    if [ "$INC_BACKUP" = "yes" ]; then
      vzctl snapshot $VEID --id $( uuidgen ) $VZCTL_PARAM
    elif [ "$FULL_BACKUP" = "yes" ]; then
      vzctl snapshot-list $VEID -H -o uuid | \
      while read UUID; do
        vzctl snapshot-delete $VEID --id $UUID
      done
      vzctl snapshot $VEID --id $( uuidgen ) $VZCTL_PARAM
      vzctl compact $VEID
    fi
    RSYNC_SRCS=" /vz/private/$VEID"
  fi
done

if [ "$FULL_BACKUP" = "yes" ]; then
  if (( $KEEP_COUNT > 0 )); then
    echo "KEEP_COUNT > 0; keeping backup.."
    REF_DATE=$( expr $( date --date="$( vzctl snapshot-list $VEID -H -o date | head -n1 )" +%s ) - 86400 )
    RSYNC_OPTS="--backup --backup-dir=$( date --date="@$REF_DATE" +%Y.%m.%d )"
  fi
fi

nice -n19 ionice -c3 rsync -avz -e "ssh -c arcfour" --{bwlimit=50000,ignore-times,delete-before,inplace,progress} $RSYNC_OPTS --exclude="????.??.??" $RSYNC_SRCS $DESTINATION

if [ "$FULL_BACKUP" = "yes" ]; then
  ssh $( echo $DESTINATION | cut -d\: -f1 ) "find $( echo $DESTINATION | cut -d\: -f2 )/* -maxdepth 0 -iname '????.??.??' | head -n -$KEEP_COUNT | xargs rm -rf"
fi
