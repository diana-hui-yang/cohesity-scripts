if [[ ! -d rman ]]; then
   mkdir rman
fi
cd rman
if [[ ! -d python ]]; then
   mkdir python
fi
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/backup-ora-coh-oim/linux/backup-ora-coh-oim.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/duplicate-ora-coh-oim/duplicate-ora-coh-oim.bash
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/restore-ora-coh-oim/restore-ora-coh-oim.bash
chmod 750 backup-ora-coh-oim.bash
chmod 750 duplicate-ora-coh-oim.bash
chmod 750 restore-ora-coh-oim.bash
cd python
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/pyhesity.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/cloneDirectory/cloneDirectory.py
curl -O https://github.com/bseltz-cohesity/scripts/tree/master/python/storePassword
chmod 750 cloneDirectory.py
chmod 750 storePassword.py
cd ..

