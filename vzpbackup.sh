#!/bin/bash

# DEFAULTS
DESTINATION="/vz/backup"
KEEP_COUNT=0
VERBOSE="no"
FULL_BACKUP="no"
INC_BACKUP="no"
BACKUP_VES=""
RSYNC_OPTS="${RSYNC_OPTS}"
TEMPLATES="yes"
QUIET="no"
declare -A EXCLUDES

# COMMANDLINE PARSING
shopt -s extglob
for param in "$@"; do
  value=${param#*=}
  case ${param} in
    -h|--help)
      echo "Usage: $0 [--verbose(=yes)] [--destination=<backup-destination>] [--keep-count=<keep count>] [--templates=<yes|no>] [--exclude=<VEID>] [--full or --inc(cremental)] [--all or VEIDs]"
      echo "Defaults:"
      echo "- --destination=${DESTINATION}"
      echo "- --keep-count=${KEEP_COUNT}"
      echo "- --verbose=${VERBOSE}"
      exit 0
    ;;
    --verbose|--verbose=yes)
      VERBOSE="yes"
    ;;
    --destination=*)
      DESTINATION=${value}
    ;;
    --keep=+([0-9])|--keep-count=+([0-9]))
      KEEP_COUNT=${value}
    ;;
    --full)
      FULL_BACKUP="yes"
    ;;
    --inc|--incremental)
      INC_BACKUP="yes"
    ;;
    --templates=+(yes|no))
      TEMPLATES=${value}
    ;;
    --quiet=+(yes|no))
      QUIET=${value}
    ;;
    --exclude=*)
      for VEID in ${value//\,/ }; do
        EXCLUDES[${VEID}]=${VEID}
      done
    ;;
    --exclude-dir=*)
        RSYNC_OPTS="${RSYNC_OPTS} --exclude=${value}"
    ;;
    --all)
      for VEID in $( prlctl list -aHo name ); do
        BACKUP_VES="${BACKUP_VES} ${VEID}"
      done
    ;;
    *)
      BACKUP_VES="${BACKUP_VES} ${param}"
    ;;
  esac
done
shopt -u extglob

# CHECKS
if [ "${BACKUP_VES}" = "" ]; then
  echo "Neither --all or VEIDs is/are given.."
  exit 1
fi

if [ "${INC_BACKUP}" = "no" ] && [ "${FULL_BACKUP}" = "no" ]; then
  echo "Neither --inc(remental) or --full given.."
  exit 1
fi

if ! which prlctl &>/dev/null; then
  echo "Couldn't find prlctl in \$PATH. Are you sure it's there?"
  exit 1
fi

if [ "${TEMPLATES}" = "yes" ]; then
  # HACK: Dirty hack to include vmtemplates in backups
  RSYNC_OPTS="${RSYNC_OPTS} $(prlctl list -tHoname | while read TPL; do prlctl list -i $TPL | grep ^Home | awk '{printf "--include=" $NF"* "}'; done)"
  TEMPLATE_DIR=$( source /etc/vz/vz.conf; echo ${TEMPLATE} )
  RSYNC_OPTS="${RSYNC_OPTS} --include=${TEMPLATE_DIR}/*"
fi

if [ "${INC_BACKUP}" = "yes" ]; then
  RSYNC_OPTS="${RSYNC_OPTS} --ignore-existing"
fi

if [ "${VERBOSE}" = "yes" ]; then
  RSYNC_OPTS="${RSYNC_OPTS} --verbose --progress"
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

# SYSLOGGING
if [ "${QUIET}" == "yes" ]
then
  exec 1> >(exec logger -t vzpbackup) 2>&1
else
  exec 1> >(exec logger -s -t vzpbackup) 2>&1
fi

# SCRIPT
for VEID in ${BACKUP_VES}; do
  if [ "x${EXCLUDES[${VEID}]}" = "x" ]; then
    VE_PRIVATE=$(prlctl list -i ${VEID} 2>&1 | sed -rn 's/^Home: (.*)/\1/p')
    if [ "x${VE_PRIVATE}" != "x" ]; then
      VE_STATE=$(prlctl list -H -o status ${VEID})
      if [ "${VE_STATE}" == "running" ]
      then
        prlctl exec ${VEID} "test -x /root/pre_snapshot.sh && bash /root/pre_snapshot.sh"
      fi
      if [ "${INC_BACKUP}" = "yes" ]; then
        echo "Creating snapshot for ${VEID}"
        prlctl snapshot ${VEID}
        if [ $? -gt 0 ]
        then
          echo "Failed to create snapshot for ${VEID}"
          rm -rf ${VE_PRIVATE}/dump/*.fail
        fi
      elif [ "${FULL_BACKUP}" = "yes" ]; then
        prlctl snapshot-list ${VEID} -H | awk '{print $NF}' | egrep -o '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}' | \
        while read UUID; do
          echo "Deleting snapshot ${UUID} from ${VEID}"
          prlctl snapshot-delete ${VEID} --id ${UUID}
        done
        echo "Creating snapshot for ${VEID}"
        prlctl snapshot ${VEID}
        if [ $? -gt 0 ]
        then
          echo "Failed to create snapshot for ${VEID}"
          rm -rf ${VE_PRIVATE}/dump/*.fail
        fi
      fi
      if [ "${VE_STATE}" == "running" ]
      then
        prlctl exec ${VEID} "test -x /root/post_snapshot.sh && bash /root/post_snapshot.sh"
      fi
      RSYNC_OPTS="${RSYNC_OPTS} --include=${VE_PRIVATE}"
    fi
  fi
done

if [ "${FULL_BACKUP}" = "yes" ]; then
  if (( ${KEEP_COUNT} > 0 )); then
    echo "KEEP_COUNT > 0; keeping backup.."
    RSYNC_OPTS="${RSYNC_OPTS} --backup --backup-dir=${DESTINATION}/$( date +%Y.%m.%d )"
  fi
  RSYNC_OPTS="${RSYNC_OPTS} --delete"
fi

rsync -az ${RSYNC_OPTS} --exclude="/vz/*/*" /vz ${DESTINATION}

if [ "${FULL_BACKUP}" = "yes" ]; then
  ssh $( echo ${DESTINATION} | cut -d\: -f1 ) "find $( echo ${DESTINATION} | cut -d\: -f2 )/* -maxdepth 0 -iname '????.??.??' | head -n -${KEEP_COUNT} | xargs rm -rf"
fi
