#!/bin/bash

# DEFAULTS
DESTINATION="/vz/backup"
KEEP_COUNT=0
VERBOSE="no"
FULL_BACKUP="no"
INC_BACKUP="no"
BACKUP_VES=""
RSYNC_OPTS="$RSYNC_OPTS"
TEMPLATES="yes"
declare -A EXCLUDES

# COMMANDLINE PARSING
shopt -s extglob
for param in "$@"; do
  value=${param#*=}
  case $param in
    -h|--help)
      echo "Usage: $0 [--verbose(=yes)] [--destination=<backup-destination>] [--keep-count=<keep count>] [--templates=<yes|no>] [--exclude=<VEID>] [--full or --inc(cremental)] [--all or VEIDs]"
      echo "Defaults:"
      echo "- --destination=$DESTINATION"
      echo "- --keep-count=$KEEP_COUNT"
      echo "- --verbose=$VERBOSE"
      exit 0
    ;;
    --verbose|--verbose=yes)
      VERBOSE="yes"
    ;;
    --destination=*)
      DESTINATION=$value
    ;;
    --keep-count=+([0-9]))
      KEEP_COUNT=$value
    ;;
    --full)
      FULL_BACKUP="yes"
    ;;
    --inc|--incremental)
      INC_BACKUP="yes"
    ;;
    --templates=+(yes|no))
      TEMPLATES=$value
    ;;
    --exclude=+([0-9]|\,))
      for VEID in ${value//\,/ }; do
        EXCLUDES[$VEID]=$VEID
      done
    ;;
    --all)
      for VEID in $( vzlist -a -H -o ctid ); do
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

if ! which prlctl &>/dev/null; then
  echo "Couldn't find prlctl in \$PATH. Are you sure it's there?"
  exit 1
fi

if [ "$TEMPLATES" = "yes" ]; then
  # HACK: Dirty hack to include vmtemplates in backups
  RSYNC_OPTS="$RSYNC_OPTS $(prlctl list -tHoname | while read TPL; do prlctl list -i $TPL | grep ^Home | awk '{printf "--include=" $NF"* "}'; done)"
  TEMPLATE_DIR=$( source /etc/vz/vz.conf; echo $TEMPLATE )
  RSYNC_OPTS="$RSYNC_OPTS --include=$TEMPLATE_DIR/*"
fi

if [ "$INC_BACKUP" = "yes" ]; then
  RSYNC_OPTS="$RSYNC_OPTS --exclude=$( VEID=; source /etc/vz/vz.conf; echo "$VE_PRIVATE*/root.hdd/root.hdd" )"
fi

if [ "$VERBOSE" = "yes" ]; then
  RSYNC_OPTS="$RSYNC_OPTS --verbose"
fi

# LOCKFILE
if [ -f /var/run/vzbackup.pid ]
then
  OLD_PID=$( cat /var/run/vzbackup.pid )
  if [ -d /proc/${OLD_PID} ]
  then
    echo "There's already a backup running.. Aborting.."
    pstree -p $( cat /var/run/vzbackup.pid )
    exit 0
  else
    echo "Mh. There's a lockfile. But no backup is running.. Ignoring it.."
  fi
fi
echo $$ > /var/run/vzbackup.pid
trap "rm /var/run/vzbackup.pid" EXIT

# SCRIPT
for VEID in $BACKUP_VES; do
  if [ "x${EXCLUDES[$VEID]}" = "x" ]; then
    if [ -f "/etc/vz/conf/$VEID.conf" ]; then
      VE_PRIVATE=$( source /etc/vz/conf/$VEID.conf; echo $VE_PRIVATE )
      if [ "$INC_BACKUP" = "yes" ]; then
        prlctl snapshot $VEID
      elif [ "$FULL_BACKUP" = "yes" ]; then
        prlctl snapshot-list $VEID -H | awk '{print $NF}' | egrep -o '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{8}' | \
        while read UUID; do
          prlctl snapshot-delete $VEID --id $UUID
        done
        prlctl snapshot $VEID
      fi
      RSYNC_OPTS="$RSYNC_OPTS --include=$VE_PRIVATE"
    fi
  fi
done

if [ "$FULL_BACKUP" = "yes" ]; then
  if (( $KEEP_COUNT > 0 )); then
    echo "KEEP_COUNT > 0; keeping backup.."
    REF_DATE=$( expr $( date --date="$( grep -m1 '<DateTime>' $(prlctl list -i $VEID | grep ^Home | cut -d' ' -f2)/Snapshots.xml | sed -rn 's/.*>(.*)<.*/\1/p' )" +%s ) - 86400 )
    RSYNC_OPTS="--backup --backup-dir=$( date --date="@$REF_DATE" +%Y.%m.%d )"
  fi
fi

rsync -az $RSYNC_OPTS --exclude="/vz/*/*" /vz $DESTINATION

if [ "$FULL_BACKUP" = "yes" ]; then
  ssh $( echo $DESTINATION | cut -d\: -f1 ) "find $( echo $DESTINATION | cut -d\: -f2 )/* -maxdepth 0 -iname '????.??.??' | head -n -$KEEP_COUNT | xargs rm -rf"
fi
