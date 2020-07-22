mkdir rman coh
cd rman
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-oim/backup-ora-coh-oim.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/duplicate-ora-coh-oim/duplicate-ora-coh-oim.bash
chmod 750 backup-ora-coh-oim.bash
chmod 750 duplicate-ora-coh-oim.bash
cd ../coh
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/nfs-mount/nfs-mount.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/prepare-restore/prepare-restore.bash
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/pyhesity.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/backupNow/backupNow.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/cloneView/cloneView.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/cloneDirectory/cloneDirectory.py
chmod +x nfs-mount.bash
chmod +x prepare-restore.bash
chmod +x backupNow.py
chmod +x cloneView.py
chmod +x cloneDirectory.py
cd ..
