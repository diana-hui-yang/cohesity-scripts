mkdir rman coh
cd rman
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-dedup/backup-ora-coh-dedup.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-dedup/restore-ora-coh-dedup.bash
chmod 750 backup-ora-coh-dedup.bash
chmod 750 restore-ora-coh-dedup.bash
cd ../coh
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/nfs-mount/nfs-mount.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/delete-ora-expired/delete-ora-expired.bash
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/pyhesity.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/backupNow/backupNow.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/cloneView/cloneView.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/cloneDirectory/cloneDirectory.py
chmod +x nfs-mount.bash
chmod +x delete-ora-expired.bash
chmod +x backupNow.py
chmod +x cloneView.py
chmod +x cloneDirectory.py
cd ..
