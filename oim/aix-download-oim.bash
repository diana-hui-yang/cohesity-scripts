if [[ ! -d rman ]]; then
   mkdir rman
fi
cd rman
if [[ ! -d python ]]; then
   mkdir python
fi
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/backup-ora-coh-oim/aix/backup-ora-coh-oim.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/duplicate-ora-coh-nfs/aix/duplicate-ora-coh-nfs.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/restore-ora-coh-nfs/aix/restore-ora-coh-nfs.bash
chmod 750 backup-ora-coh-oim.bash
chmod 750 duplicate-ora-coh-nfs.bash
chmod 750 restore-ora-coh-nfs.bash
cd python
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/pyhesity.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/cloneDirectory/cloneDirectory.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/storePassword/storePassword.py
chmod 750 cloneDirectory.py
chmod 750 storePassword.py
cd ..
