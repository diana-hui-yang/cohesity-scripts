mkdir rman coh

cd rman
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-sbt/backup-ora-coh-sbt.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/duplicate-ora-coh-sbt.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/restore-ora-coh-sbt.bash
chmod 750 backup-ora-coh-sbt.bash
chmod 750 duplicate-ora-coh-sbt.bash
chmod 750 restore-ora-coh-sbt.bash
cd ../coh
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/nfs-mount/nfs-mount.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/delete-ora-expired/delete-ora-expired.bash
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/pyhesity.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/backupNow/backupNow.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/cloneView/cloneView.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/cloneDirectory/cloneDirectory.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/deleteView/deleteView.py
chmod +x nfs-mount.bash
chmod +x delete-ora-expired.bash
chmod +x backupNow.py
chmod +x cloneView.py
chmod +x cloneDirectory.py
chmod +x deleteView.py
cd ..
