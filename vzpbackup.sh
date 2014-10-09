#!/bin/bash

# DEFAULTS

DESTINATION="/vz/backup"
KEEP_COUNT=0

# COMMANDLINE PARSING

for param in "$@"; do
  case $param in
    --destination=*)
      DESTINATION=${param#*=}
    ;;
  esac
done

# make sure we only run once
test -f /var/run/vzbackup.pid && exit 0
touch /var/run/vzbackup.pid
trap "rm /var/run/vzbackup.pid" EXIT

VZLIST="$( vzlist -H )"

if [ "$1"  = "--inc" ] || [ "$1" = "--incremental" ]; then
  while read LINE; do
    read VEID REST <<< $LINE
    vzctl snapshot $VEID --id $( uuidgen ) --skip-suspend
  done <<< "$VZLIST"
#  RSYNC_OPTS="--exclude=*/root.hdd/root.hdd"
elif [ "$1"  = "--full" ]; then
  while read LINE; do
    read VEID REST <<< $LINE
    vzctl snapshot-list $VEID -H -o uuid | \
    while read UUID; do
      vzctl snapshot-delete $VEID --id $UUID
    done
    vzctl snapshot $VEID --id $( uuidgen ) --skip-suspend 
    vzctl compact $VEID
  done <<< "$VZLIST"
  if (( $KEEP_COUNT > 0 )); then
    echo "KEEP_COUNT > 0; keeping backup.."
    REF_DATE=$( expr $( date --date="$( vzctl snapshot-list $VEID -H -o date | head -n1 )" +%s ) - 86400 )
    RSYNC_OPTS="--backup --backup-dir=$( date --date="@$REF_DATE" +%Y.%m.%d )"
  fi
else
  echo "Usage: $0 [--inc(remental)|--full]"
  exit 0
fi

nice -n19 ionice -c3 rsync -avz -e "ssh -c arcfour" --{bwlimit=50000,ignore-times,delete-before,inplace,progress} $RSYNC_OPTS --exclude="????.??.??" --exclude="/vz/"{dump,lock,root,vztmp}"/*" /vz $DESTINATION

if [ "$1" = "--full" ]; then
  ssh $( echo $DESTINATION | cut -d\: -f1 ) "find $( echo $DESTINATION | cut -d\: -f2 )/* -maxdepth 0 -iname '????.??.??' | head -n -$KEEP_COUNT | xargs rm -rf"
fi
