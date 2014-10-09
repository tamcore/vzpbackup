#!/bin/bash

# DEFAULTS
DESTINATION="/vz/backup"
KEEP_COUNT=0
SUSPEND="no"
FULL_BACKUP="no"
INC_BACKUP="no"
VZCTL_PARAM=""

# COMMANDLINE PARSING
shopt -s extglob
for param in "$@"; do
  case $param in
    -h|--help)
      echo "Usage: $0 [--destination=<backup-destination>] [--keep-count=<keep count>] [--suspend=<yes|no>]"
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
  esac
done
shopt -u extglob

# LOCKFILE
test -f /var/run/vzbackup.pid && exit 0
touch /var/run/vzbackup.pid
trap "rm /var/run/vzbackup.pid" EXIT

# SCRIPT
VZLIST="$( vzlist -H )"

if [ "$INC_BACKUP" = "yes" ]; then
  while read LINE; do
    read VEID REST <<< $LINE
    vzctl snapshot $VEID --id $( uuidgen ) $SUSPEND
  done <<< "$VZLIST"
elif [ "$FULL_BACKUP" = "yes" ]; then
  while read LINE; do
    read VEID REST <<< $LINE
    vzctl snapshot-list $VEID -H -o uuid | \
    while read UUID; do
      vzctl snapshot-delete $VEID --id $UUID
    done
    vzctl snapshot $VEID --id $( uuidgen ) $SUSPEND
    vzctl compact $VEID
  done <<< "$VZLIST"
  if (( $KEEP_COUNT > 0 )); then
    echo "KEEP_COUNT > 0; keeping backup.."
    REF_DATE=$( expr $( date --date="$( vzctl snapshot-list $VEID -H -o date | head -n1 )" +%s ) - 86400 )
    RSYNC_OPTS="--backup --backup-dir=$( date --date="@$REF_DATE" +%Y.%m.%d )"
  fi
fi

nice -n19 ionice -c3 rsync -avz -e "ssh -c arcfour" --{bwlimit=50000,ignore-times,delete-before,inplace,progress} $RSYNC_OPTS --exclude="????.??.??" --exclude="/vz/"{dump,lock,root,vztmp}"/*" /vz $DESTINATION

if [ "$FULL_BACKUP" = "yes" ]; then
  ssh $( echo $DESTINATION | cut -d\: -f1 ) "find $( echo $DESTINATION | cut -d\: -f2 )/* -maxdepth 0 -iname '????.??.??' | head -n -$KEEP_COUNT | xargs rm -rf"
fi
