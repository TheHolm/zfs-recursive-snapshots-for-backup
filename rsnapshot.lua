
--[[] run as
sudo zfs program -j pool_name ./rsnapshot.lua root_dataset [mount_root] [flag to check] > snapshot.json'
pool_name  - name of the poll where target datasets are located
root_dataset  - from where start creating snaphot. "root_dataset" must be in "pool_name"
[mount_root] - optional. default is None. path where backup directories will be created
[flag_to_check] optional. default backup:dataset. valid values are [true,false]. Backup all child dataset unless "flag_to_check" user property set to "false"

!!  If snapshot with given name already existis, script will not create a new smapshot, it will reuse existing. If it not what you want destroy backup snapshots manually.

zfs will greate a snapshot.json file.
following command will output shell script to create backup folders.
jq -rS '.return[].mount' snapshot.json | jq -r '.[]'

adter you backed up
jq -rS '.return[].mount' snapshot.json | jq -r '.[]'
will output shell script to unmount snapshots ( but not remove them) nad destroy backup folder


backup folders structure:
dataset_guid/dataset_path
example 10262689525400274831/data

also 3 files will be created
dataset_guid/properties.json - listed all local properties of the dataset
dataset_guid/before_restore.sh - shell script to create mount directory and dataset and set zfs properies. It will do it at same path and pool as directory created for backup. It may be not what you want.
dataset_guid/after_restore.sh - shell script, unmount dataset, destroy directory and set "mountpoint" on dataset to how it was during backup.
]]

function snapshots_recursive(root)
    has_children_to_snapshot = false
    for child in zfs.list.children(root) do
        has_children_to_snapshot = snapshots_recursive(child) or has_children_to_snapshot
    end
    create_snapshot = true
    for property,value in  zfs.list.user_properties(root) do
          if property == flag then
              if value == "false" then
                  create_snapshot = false
              end
              break
          end
    end

    -- snapshot dataset where create_snapshot is true and record properties where create_snapshot or has_children_to_snapshot is true. If both create_snapshot and has_children_to_snapshot are false, datased is ignored
    if ( has_children_to_snapshot or create_snapshot ) == false then
      return false
    end

    vtype , source = zfs.get_prop(root,'type')
    if vtype == 'filesystem' then -- Not snapshoting volumes, but will run over all tree to collect properties
       results[root] = {}
       if create_snapshot and (not zfs.exists(root .. '@' .. flag)) then
         err = zfs.sync.snapshot(root .. '@' .. flag)
         results[root]['error code'] =  err
       else
         err = 0
       end
       if err == 0 then
         guid , source = zfs.get_prop(root,'guid')
         guid_str = string.format("%u",guid)
         results[root]['mount'] = {}
         results[root]['unmount'] = {}
         if create_snapshot then
           results[root]['mount'][0] = 'mkdir -p "' .. mount_to .. guid_str .. '/data"'
           results[root]['mount'][1] = 'mount -t zfs "' .. root  .. '@' .. flag .. '" "' .. mount_to .. guid_str .. '/data"'
           results[root]['unmount'][0] = 'umount "' .. mount_to .. guid_str .. '/data"'
           results[root]['unmount'][1] = 'rm -rf "' .. mount_to .. guid_str .. '"'
         else -- only to record porperties
           results[root]['mount'][0] = 'mkdir -p "' .. mount_to .. guid_str .. '"'
           results[root]['unmount'][0] = 'rm -rf "' .. mount_to .. guid_str .. '"'
         end
         -- get list of localy defined system properties
         property_set = {} -- will be stored in json
         zfs_set = '-o mountpoint="' .. mount_to .. guid_str .. '/data" ' -- for resrore sh script
         properties_list = zfs.list.system_properties(root)
         for n,property in ipairs(properties_list) do
           value , source = zfs.get_prop(root, property)
           if source == root then -- property are (re)defined locally
              property_set[property] = value
              if property ~= "mountpoint" then
                zfs_set = zfs_set .. property .. '="' .. value .. '" '
              end
           end
         end  -- for
         -- get list of localy def ined user properties
         for property,value in  zfs.list.user_properties(root) do
           value , source = zfs.get_prop(root, property)
           if source == root then -- property are (re)defined locally
              property_set[property] = value
              zfs_set = zfs_set .. "-o " .. property .. '="' .. value .. '" '
           end
         end
         results[root]['config'] = {}
         results[root]['config']['path'] = root
         results[root]['config']['guid'] = guid_str
         results[root]['config']['properties'] = property_set
         results[root]['mount'][3] = "jq -Sr '.return." .. '"' .. root .. '"' .. ".config' snapshot.json > " .. mount_to .. guid_str .. '/properties.json'

         -- before_restore.sh create dataset on same path and mount it for restore
         results[root]['before_restore'] = {}
         results[root]['before_restore'][0] = 'mkdir -p "' .. mount_to .. guid_str .. '/data"'
         results[root]['before_restore'][1] = "zfs create " .. zfs_set .. '"' .. root .. '"'
         results[root]['mount'][4] = "jq -Sr '.return." .. '"' .. root .. '"' .. ".before_restore' snapshot.json | jq -r '.[]' > " .. mount_to .. guid_str .. '/before_restore.sh'

         -- after_restore.sh unmount dataset, remome teporary file and set "mountpoint" how it was
         results[root]['after_restore'] = {}
         results[root]['after_restore'][0] = 'umount "' .. mount_to .. guid_str .. '/data"'
         results[root]['after_restore'][1] = 'rm -rf "' .. mount_to .. guid_str .. '"'
         if results[root]['config']['properties']['mountpoint'] == nil then
           results[root]['after_restore'][2] = 'zfs inherit mountpoint "' .. root .. '"'
         else
           results[root]['after_restore'][2] = 'zfs set mountpoint="' .. results[root]['config']['properties']['mountpoint'] .. '" "' .. root .. '"'
         end
         results[root]['mount'][5] = "jq -Sr '.return." .. '"' .. root .. '"' .. ".after_restore' snapshot.json | jq -r '.[]' > " .. mount_to .. guid_str .. '/after_restore.sh'

       end
    end
    return true
end


args = ...
argv = args["argv"]

if argv[2] ~= nil then
  mount_to = argv[2] .. '/'
else
  mount_to = ""
end

if argv[3] ~= nil then
  flag =  argv[3]
else
  flag = "backup:dataset"
end

results = {}

snapshots_recursive(argv[1])

return results
