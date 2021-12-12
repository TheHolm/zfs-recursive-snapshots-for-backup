# ZFS recursive snapshots for backup
LUA script for "zfs program" to create snapshots recursively and mount them nicely to backup. Useful when you can't use *zfs send* and  *zfs receive* for backup

# How to use

## Run LUA script to creates snapshots
Run
```
sudo zfs program -j pool_name ./rsnapshot.lua root_dataset [backup_root] [flag to check] > snapshot.json'
```
* *pool_name*  - name of the poll where target datasets are located
* *root_dataset*  - from where start creating snapshot. * *root_dataset* must be in *pool_name*
* *backup_root* - optional. default is "./". path where backup directories will be created.
* *flag_to_check* optional. default backup:dataset. valid values are [true,false]. Script will backup all child dataset unless "flag_to_check" user property set to "false"

Script will descent down from *root_dataset* and create snapshots *flag_to_check*@dataset_name on all datasets which are marked for backup. (i.e. do not have *flag_to_check* user property set to "false") Also it will output all local properties and some other info on STDOUT. If dataset is not marked for backup but has descendants (children, grandchildren) which are marked for backup, no snapshots will be created but properties will be recorded.
Datasets which are not marked for backup and without backed up  descendants will be ignored.

**!!  If snapshot with given name already exists, script will not create a new snapshot, it will reuse existing. !!** If it is not what you want, destroy backup snapshots manually in advance.

## Create backup folder structure and mount snapshots to it

*snapshot.json* contains all info required to work with backup folder structure. You will need [Jq](https://github.com/stedolan/jq) tool to parse it. It is usually packaged for distro.

```
jq -rS '.return[].mount' snapshot.json | jq -r '.[]'
```
will output shell script to create backup folders and mount snapshots to them and also create some useful files.
Examine the output, and if you dire pipe it to root shell for execution

**!! Piping anything to root shell is dangerous !!**
No attempts was made to sanitise input. Anyone who can set names of datasets you are trying to backup can harm your system. Trying to backup dataset named *tank/hello";rm -rf /;"* will wipe your system. Be careful, backing up dataset received via *zfs send|receive" opens your system to exploits from sending end if you use this script.

After shell is completed you should get all your snapshots mounted under *backup_root*.
Snapshot which need to be backed up will be mounted under *backup_root/dataset_guid/data*. where *dataset_guid* is guid of dataset(not snapshot) to be backed up.
as example:
```
/to_backup/10262689525400274831/data
```
why guid in the path? It is unique, does not change and guarantee that it will be no clashes  

Also 3 files will be created in *backup_root/dataset_guid/* for **all** dataset including not backup parents of backed up datasets.
* *dataset_guid/properties.json* - listed all local properties of the dataset. Just to be used by your script if required.
* *dataset_guid/before_restore.sh* - shell script to create mount directory, dataset itself and set zfs properties with exception of "mountpoint". It will do it at same path and pool as directory created for backup. Please do not try to use it as is. It may be not what you want. This is why *properties.json* is there.
* *dataset_guid/after_restore.sh* - shell script to unmount dataset, destroy directory and set "mountpoint" on dataset to how it was during backup.

# Backup it
Just backup backup *backup_root/* by whatever system are you using for backup.

# Cleanup after backup

```jq -rS '.return[].unmount' snapshot.json | jq -r '.[]'```

same story as before. Pipe it to root shell to unmount snapshots ( but not remove them) and destroy backup folders.
