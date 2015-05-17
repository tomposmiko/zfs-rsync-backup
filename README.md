zfs rsync backup
----------------
zrb (*Z*FS *R*sync *B*ackup) is a simple and rough solution to organize snapshots with the 'zfs snapshot' command.

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
