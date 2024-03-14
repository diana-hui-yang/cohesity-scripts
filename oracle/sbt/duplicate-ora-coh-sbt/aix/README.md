## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oracle/sbt/duplicate-ora-coh-sbt/aix/aix-duplicate-ora-coh-sbt.bash
- chmod 750 aix-duplicate-ora-coh-sbt.bash

## Description
The scripts clone database uses Cohesity Source-side dedup library, and from the backup files created by script backup-ora-coh-sbt.bash

When run the script without any options, it displays the script usage

Required parameters

- -i : Target Oracle instance name (Oracle duplicate database)
- -r : Source Oracle connection (example: "<dbuser>/<dbpass>@<target db connection>")
- -h : Source host - Oracle database host that the backup was run.
- -d : Source Oracle_DB_Name (database backup was taken). It is DB name, not instance name if it is RAC or DataGuard
- -t : Point in Time (format example: "2019-01-27 13:00:00")
- -e : Sequence
- -y : Cohesity Cluster DNS name
- -v : Cohesity view

Optional Parameters
  
- -c : Catalog connection (example: "<dbuser>/<dbpass>@<catalog connection string>", optional)
- -b : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b';
- -p : number of channels (default is 4), optional
- -j : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)
- -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_6_and_7_linux-x86_64.so, default directory is lib)
- -o : ORACLE_HOME (default is current environment), optional
- -u : Source pluggable database (if this input is empty, it is standardalone or CDB database restore)
- -f : yes means force. It will refresh the target database without prompt
- -g : yes means encryption-in-flight is used. The default is no
- -k : encryption certificate file directory, default directory is lib
- -x : yes means gRPC is used. no means SunRPC is used. The default is yes
- -w : yes means preview rman duplicate scripts
 

## file contains duplicate setting
set newname for database to "'+DATA';"

## duplicate exmaple

### duplidate none CDB database example when sbt library is in lib directory under the script directory
- ./aix-duplicate-ora-coh-sbt.bash -r "user/password@orawest2:/w2sigb" -h orawest2 -d w2sigb -i w2sigc -y cohesity -v ora_sbt
### duplidate PDB database when sbt library is in lib directory under the script directory
- ./aix-duplicate-ora-coh-sbt.bash -r "user/password@orawest2:/cohcdbb" -h orawest2 -d cohcdbb -i cohcdbc -u orapdb1  -y cohesity -v ora_sbt 
