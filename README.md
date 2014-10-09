# vzpbackup

Backupscript for for OpenVZ containers using Ploop storage.

The backupscript was initially based on the Image-based backup section of [openvz.org/Ploop/Backup](http://openvz.org/Ploop/Backup)

## Requirements

* OpenVZ containers using Ploop for storage
* and a few commandline tools (bash, cut, date, expr, rsync, ssh, touch, uuidgen)

## BACKUP: vzpbackup.sh

### Commandline parameters

--destination=\<backup destination\>

	Allows to specifiy an rsync-compatible backup destination.
	Default is /vz/backup

--keep-count=\<keep count\>

	Allows to specify how many fullbackups including incremental
	backups based on them are held on stock
	Default is 0

--suspend=\<yes|no\>

	Allows to specify whether a container should be suspended during
	snapshot creation or not. If yes is given, the containers memory
	is included in the snapshot.
	Default is no

## RESTORE: vzprestore.sh (coming in the next months)

## AUTHOR
Philipp 'TamCore' Born <philipp {at} tamcore {dot} eu>

## License
[GNU GENERAL PUBLIC LICENSE v2](LICENSE)