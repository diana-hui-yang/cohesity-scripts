mkdir rman
cd rman
mkdir python
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/backup-ora-coh-oim/sun/sbackup-ora-coh-oim.bash
chmod 750 backup-ora-coh-oim.bash
cd python
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/pyhesity.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/cloneDirectory/cloneDirectory.py
curl -O https://github.com/bseltz-cohesity/scripts/tree/master/python/storePassword
chmod 750 cloneDirectory.py
chmod 750 storePassword.py
cd ..
