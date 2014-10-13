#!/bin/bash

# DEFAULTS
SOURCE="/vz/backup"
RSYNC_OPTS=""
TEMPLATES="yes"
RESTORE_VES=""

# COMMANDLINE PARSING
shopt -s extglob
for param in "$@"; do
  case $param in
    -h|--help)
      echo "Usage: $0 [--source=<backup-source>] [--templates=<yes|no>] [--all or VEIDs]"
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
    --all)
      for VEID in $( vzlist -H -o ctid ); do
        RESTORE_VES="$RESTORE_VES $VEID"
      done
    ;;
    +([0-9]))
      RESTORE_VES="$RESTORE_VES $param"
    ;;
  esac
done
shopt -u extglob

# CHECKS
if [ "$RESTORE_VES" = "" ]; then
  echo "Neither --all or VEIDs is/are given.."
  exit 1
fi

if ! which vzctl &>/dev/null; then
  echo "Couldn't find vzctl in \$PATH. Are you sure it's there?"
  exit 1
fi

# SCRIPT
for VEID in $RESTORE_VES; do
  RESTORE_SOURCES="$RESTORE_SOURCES $SOURCE/vz/private/$VEID"
done

nice -n19 ionice -c3 rsync -avz -e "ssh -c arcfour" --{bwlimit=50000,ignore-times,delete-before,inplace,progress} $RESTORE_SOURCES /vz/private

if [ "$TEMPLATES" = "yes" ]; then
  TEMPLATE_DIR=$( source /etc/vz/vz.conf; echo $TEMPLATE )
  nice -n19 ionice -c3 rsync -avz -e "ssh -c arcfour" --{bwlimit=50000,ignore-times,delete-before,inplace,progress} $SOURCE$TEMPLATE_DIR/ /vz$TEMPLATE_DIR/
fi