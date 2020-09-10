mkdir rman coh
cd rman
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/backup-ora-coh-oim/backup-ora-coh-oim.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/duplicate-ora-coh-oim/duplicate-ora-coh-oim.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/restore-ora-coh-oim/restore-ora-coh-oim.bash
chmod 750 backup-ora-coh-oim.bash
chmod 750 duplicate-ora-coh-oim.bash
chmod 750 restore-ora-coh-oim.bash
cd ../coh
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/nfs-mount/nfs-mount.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/prepare-restore/prepare-restore.bash
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/pyhesity.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/backupNow/backupNow.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/cloneView/cloneView.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/cloneDirectory/cloneDirectory.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/easyScript/storePassword/python/storePassword.py
chmod 750 nfs-mount.bash
chmod 750 prepare-restore.bash
chmod 750 backupNow.py
chmod 750 cloneView.py
chmod 750 cloneDirectory.py
chmod 750 storePassword.py
cd ..

