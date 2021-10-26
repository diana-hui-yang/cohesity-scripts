if [[ ! -d rman ]]; then
  mkdir rman
fi
cd rman
if [[ ! -d python ]]; then
  mkdir python
fi
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/backup-ora-coh-oim/sun/sbackup-ora-coh-oim.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/duplicate-ora-coh-nfs/sun/sun-duplicate-ora-coh-nfs.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/restore-ora-coh-nfs/sun/sun-restore-ora-coh-nfsbash
chmod 750 sbackup-ora-coh-oim.bash
chmod 750 sun-duplicate-ora-coh-nfs.bash
chmod 750 sun-restore-ora-coh-nfs.bas
cd python
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/pyhesity.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/cloneDirectory/cloneDirectory.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/storePassword/storePassword.py
chmod 750 cloneDirectory.py
chmod 750 storePassword.py
cd ..
