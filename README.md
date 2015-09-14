zfs rsync backup
----------------
zrb (*Z*FS *R*sync *B*ackup) is a simple and rough solution to manage backup with the 'rsync' + 'zfs snapshot' commands.
It is running from a central backup server and works pull mode.

Features:
- pull mode backup
- resuming backup job ot of box
- excluding via rsync exclude file
- optionally different pool/dataset name
- various expiring rules
- parallel jobs with configurable process number
- command to add and list vaults

USAGE
=====

#### dictionary
VAULT: backup directory where backed up data and config files kept.
Each VAULT has 3 directories:
config/ -> per VAULT config files
data/ -> copied data
log/ -> logs

#### init
- local (mounted) directory

$ zrb.sh -a /path/to/backup/source -v VAULT

- remote source (rsync syntax)

$ zrb.sh -a hostname:/ -v VAULT


Initializes zfs dataset of the VAULT and necessary directories and define rsync source.

#### manual running
$ zrb.sh-v VAULT

#### expiring
- expire only:

zrb.sh-e only -v VAULT

- backup + expire:

zrb.sh-e yes -v VAULT

#### cron job
$ cp zrb-ruanall /etc/cron.d/

$ chmod 644 /etc/cron.d/zrb-runall

Change whatever timing and frequency (eg. hourly, daily, weekly, monthly) you prefer.

#### listing
$ zrb.sh -l VAULT
