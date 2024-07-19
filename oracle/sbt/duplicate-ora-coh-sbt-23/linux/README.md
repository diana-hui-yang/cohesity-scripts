## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/sbt/duplicate-ora-coh-sbt-23/linux/duplicate-ora-coh-sbt-23.bash
- chmod 750 duplicate-ora-coh-sbt-23.bash

## Description
The scripts clone database uses Cohesity Source-side dedup library, and from the backup files created by script backup-ora-coh-sbt.bash

When run the script without any options, it displays the script usage

Required parameters
- -i : Target Oracle instance name (Oracle duplicate database)
- -r : Source Oracle connection (example: "sys/<password>@<target db connection>" or "<dbuser>/<dbpass>@<target connection string> as sysbackup")
- -h : Source host - Oracle database host that the backup was run.
- -y : Cohesity Cluster DNS name
- -v : Cohesity View that is configured to be the target for Oracle backup
- -q : Cohesity View that is configured to be the Cohesity catalog for Oracle backup

Optional Parameters
  
- -e : Log sequence number. Either point-in-time or log sequence number. Can't be both.
- -c : Catalog connection (example: "<dbuser>/<dbpass>@<catalog connection string>", optional)
- -t : Point in Time (format example: "2019-01-27 13:00:00")
- -b : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b';
- -p : number of channels (default is 4), optional
- -j : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)
- -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_6_and_7_linux-x86_64.so, default directory is lib)
- -o : ORACLE_HOME (default is current environment), optional
- -u : Source pluggable database (if this input is empty, it is standardalone or CDB database restore)
- -n : Destination pluggable database
- -l : yes means plugging the pdb database with copy option. The default is nocopy which means the database file structure will not be moved from auxiliary database to target database
- -a : Auxiliary database to restore pluggable database
- -f : yes means force. It will refresh the target database without prompt
- -m : yes mean Oracle duplicate use noresume, default is no
- -g : yes means encryption-in-flight is used. The default is no
- -k : encryption certificate file directory, default directory is lib
- -x : yes means gRPC is used. no means SunRPC is used. The default is yes
- -w : yes means preview rman duplicate scripts
 

## file contains duplicate setting
set newname for database to "'+DATA';"

## duplicate exmaple

### duplidate none CDB database example when sbt library is in lib directory under the script directory
- ./duplicate-ora-coh-sbt-23.bash -r "user/password@orawest2:/w2sigb" -i w2sigc -y cohesity -v orasbt -q orasbt_catalog
### duplidate PDB database when sbt library is in lib directory under the script directory
- ./duplicate-ora-coh-sbt-23.bash -r "user/password@orawest2:/cohcdbb" -i cohcdbc -u orapdb1  -y cohesity -v orasbt_catalog 
### duplidate PDB database using a auxiliary database while target database is up running
- ./duplicate-ora-coh-sbt-23.bash -r "user/password@orawest2:/cohcdbb" -i cohcdbc -u orapdb1 -n orares1 -y cohesity -v ora_sbt -v orasbt_tatalog -a proxydb1
