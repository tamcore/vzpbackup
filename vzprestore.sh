#!/bin/bash

# DEFAULTS
SOURCE="/vz/backup"
RSYNC_OPTS="$RSYNC_OPTS"
TEMPLATES="yes"
RESTORE_VES=""
LIST_BACKUPS="no"
VE_PRIVATE="/vz/private/"

# COMMANDLINE PARSING
shopt -s extglob
for param in "$@"; do
  case $param in
    -h|--help)
      echo "Usage: $0 [--source=<backup-source>] [--templates=<yes|no>] [--list-backups] [--all or VEIDs]"
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

# SCRIPT
if [ "$LIST_BACKUPS" = "yes" ]; then
  echo "Available Backups:"
  CURRENT_SET="$( rsync $SOURCE/$VE_PRIVATE | grep -oE '[0-9]+$' )"
  echo "- Current set:"
  if [ "$CURRENT_SET" != "" ]; then
    for VEID in $CURRENT_SET; do
      echo "-- $VEID"
    done
  else
    echo "-- Current set is empty."
  fi
  BACKUP_SETS="$( rsync $SOURCE | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$' )"
  if [ "$BACKUP_SETS" != "" ]; then
    for BACKUP_SET in $BACKUP_SETS; do
      echo
      echo "- Set '$BACKUP_SET'"
      CURRENT_SET="$( rsync $SOURCE/$BACKUP_SET/$VE_PRIVATE | grep -oE '[0-9]+$' )"
      if [ "$CURRENT_SET" != "" ]; then
        for VEID in $CURRENT_SET; do
          echo "-- $VEID"
        done
      else
        echo "-- set is empty."
      fi
    done
  fi
  exit 0
fi

for VEID in $RESTORE_VES; do
  RESTORE_SOURCES="$RESTORE_SOURCES $SOURCE/vz/private/$VEID"
done

rsync -avz -e "ssh -c arcfour" --{ignore-times,delete-before,inplace} $RSYNC_OPTS $RESTORE_SOURCES /vz/private

if [ "$TEMPLATES" = "yes" ]; then
  TEMPLATE_DIR=$( source /etc/vz/vz.conf; echo $TEMPLATE )
  rsync -avz -e "ssh -c arcfour" --{ignore-times,delete-before,inplace} $RSYNC_OPTS $SOURCE$TEMPLATE_DIR/ /vz$TEMPLATE_DIR/
fi
