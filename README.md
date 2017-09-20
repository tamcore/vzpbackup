# vzpbackup

Backupscript for for OpenVZ containers using Ploop storage.

The backupscript was initially based on the Image-based backup section of [openvz.org/Ploop/Backup](http://openvz.org/Ploop/Backup)

## Requirements

* OpenVZ containers using Ploop for storage
* and a few commandline tools (bash, cut, date, expr, rsync, ssh, touch, uuidgen)

## BACKUP: vzpbackup.sh

### Commandline parameters

**--full**

	Start a new backup set with a fresh full backup. If --keep-count is
	higher than 0, the current backup set will be moved to a folder which
	is named based on the date the set was created (for ex. 2014.10.08).
	It's recommended to do a full backup monthly and a incremental daily.

**--all or VEIDs**

	Tells the script if we want to back up all VEs (--all),
	or only specified ones. If --all is set, additional passed VEIDs
	are ignored.

**--inc or --incremental**

	Start an incremental backup. Incremental means it creates a new snapshot
	for each container and transfers only the changes.

**--destination=\<backup destination\>**

	Allows to specifiy an rsync-compatible backup destination.
	Default is /vz/backup

**--keep-count=\<keep count\>**

	Allows to specify how many fullbackups including incremental
	backups based on them are held on stock
	Default is 0

**--templates=\<yes|no\>**

	If set to yes, we'll also backup our templates.
	Default is yes

**--exclude=\<veid,veid,veid\>**

	Allows to exclude certain VEs from being backed up, even if --all is given.
	Multiple VEIDs can be specified as comma separated list.

**--verbose(=\<yes\>)

    increase verbosity

## RESTORE: vzprestore.sh

**--all or VEIDs**

	Tells the script if we want to restore all backed up VEs (--all),
	or only specified ones. If --all is set, additional passed VEIDs
	are ignored.

**--source=\<backup-source\>**

	Allows to specifiy an rsync-compatbile backup source.
	Default is /vz/backup

**--templates=\<yes|no\>**

	If set to yes, we'll also restore our templates.

**--list-backups**

	Prints a list of all available backups and backupsets.

**--backup-set=\<backupset\>**

	Define from which backupset we're restoring.
	Default is the current one

## AUTHOR
Philipp 'TamCore' Born <philipp {at} tamcore {dot} eu>

## License
[GNU GENERAL PUBLIC LICENSE v2](LICENSE)
