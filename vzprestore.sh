#!/bin/bash

# DEFAULTS
SOURCE="/vz/backup"
RSYNC_OPTS="$RSYNC_OPTS"
TEMPLATES="yes"
RESTORE_VES=""
LIST_BACKUPS="no"
RESTORE_SET="."

# COMMANDLINE PARSING
shopt -s extglob
for param in "$@"; do
  case $param in
    -h|--help)
      echo "Usage: $0 [--source=<backup-source>] [--templates=<yes|no>] [--list-backups] [--backup-set=<backup-set>] [--all or VEIDs]"
      echo "Defaults:"
      echo "- --source=$SOURCE"
      echo "- --templates=$TEMPLATES"
      exit 0
    ;;
    --source=*)
      SOURCE=${param#*=}
    ;;
    --templates=+(yes|no))
      TEMPLATES=${param#*=}
    ;;
    --list-backups)
      LIST_BACKUPS="yes"
    ;;
    --all)
      RESTORE_VES="all"
    ;;
    --backup-set=*)
      RESTORE_SET=${param#*=}
    ;;
    +([0-9]))
      test "$RESTORE_VES" = "" && RESTORE_VES="$RESTORE_VES $param"
    ;;
  esac
done
shopt -u extglob

# CHECKS
if [ "$RESTORE_VES" = "" ] && [ "$LIST_BACKUPS" = "no" ]; then
  echo "No VEs to restore given.."
  exit 1
fi

if ! which vzctl &>/dev/null; then
  echo "Couldn't find vzctl in \$PATH. Are you sure it's there?"
  exit 1
fi

# FUNCTIONS
function _list_backups {
  echo "- Set '${2/^\.\$/current}'"
  CURRENT_SET="$( rsync $RSYNC_OPTS $1/$2/$3 | grep -oE '[0-9]+$' )"
  if [ "$CURRENT_SET" != "" ]; then
    for VEID in $CURRENT_SET; do
      echo "-- $VEID"
    done
  else
    echo "-- set is empty."
  fi
}

# SCRIPT
VE_PRIVATE="$( source /etc/vz/vz.conf; echo $VE_PRIVATE )"

if [ "$LIST_BACKUPS" = "yes" ]; then
  echo "Available Backups:"
  _list_backups $SOURCE . $VE_PRIVATE

  BACKUP_SETS="$( rsync $RSYNC_OPTS $SOURCE | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$' )"
  if [ "$BACKUP_SETS" != "" ]; then
    for BACKUP_SET in $BACKUP_SETS; do
      echo
      _list_backups $SOURCE $BACKUP_SET $VE_PRIVATE
    done
  fi
  exit 0
fi

if [ "$RESTORE_VES" = "all" ]; then
  RESTORE_SOURCES="$RESTORE_SOURCES $SOURCE/$RESTORE_SET/$VE_PRIVATE"
else
  for VEID in $RESTORE_VES; do
    RESTORE_SOURCES="$RESTORE_SOURCES $SOURCE/$RESTORE_SET/$VE_PRIVATE/$VEID"
  done
fi

rsync -avz $RSYNC_OPTS $RESTORE_SOURCES $VE_PRIVATE

if [ "$TEMPLATES" = "yes" ]; then
  TEMPLATE_DIR=$( source /etc/vz/vz.conf; echo $TEMPLATE )
  rsync -avz $RSYNC_OPTS $SOURCE/$RESTORE_SET/$TEMPLATE_DIR/ $TEMPLATE_DIR
fi
