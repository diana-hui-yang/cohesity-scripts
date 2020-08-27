mkdir rman coh
cd rman
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-sbt/backup-ora-coh-sbt.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/duplicate-ora-coh-sbt/duplicate-ora-coh-sbt.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/restore-ora-coh-sbt.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/delete-ora-expired/delete-ora-expired.bash
chmod 750 backup-ora-coh-sbt.bash
chmod 750 duplicate-ora-coh-sbt.bash
chmod 750 restore-ora-coh-sbt.bash
chmod 750 delete-ora-expired.bash
cd ../coh
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/pyhesity.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/backupNow/backupNow.py
chmod +x backupNow.py
cd ..
