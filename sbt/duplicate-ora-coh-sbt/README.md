## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/duplicate-ora-coh-sbt/duplicate-ora-coh-sbt.bash
- chmod 750 duplicate-ora-coh-sbt.bash

## Description
The scripts clone database uses Cohesity Source-side dedup library, and from the backup files created by script backup-ora-coh-sbt.bash

When run the script without any options, it displays the script usage

Required parameters

- -r : Target connection (example: "dbuser/dbpass@target db connection")
- -b : backup host
- -d : Source Oracle_DB_Name, If Source is not a RAC database, it is the same as Instance name. If it is RAC, it is DB name, not instance name
- -t : Target Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2
- -f : File contains duplicate setting, example: set until time "to_date("'2020-08-09 19:30:00','YYYY/MM/DD HH24:MI:SS'")";
- -v : Cohesity view

Optional Parameters

- -e : Catalog connection (example: "dbuser/dbpass@catalog connection string", optional)
- -a : target host (Optional, default is localhost)
- -i : File contains new setting to spfile. example: SET DB_CREATE_FILE_DEST +DGROUP3"
- -p : number of channels (default is 4), optional
- -j : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)
- -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_6_and_7_linux-x86_64.so, default directory is lib)
- -o : ORACLE_HOME (default is current environment), optional
- -c : Source pluggable database (if this input is empty, it is standardalone or CDB database restore)
- -w : yes means preview rman backup scripts 

## file contains duplicate setting
set newname for database to "'+DATA';"
set until time \"to_date("'2020-08-09 19:30:00','YYYY/MM/DD HH24:MI:SS'")\";

## duplicate exmaple

### duplidate none CDB database example when sbt library is in lib directory under the script directory
- ./duplicate-ora-coh-sbt.bash -r "user/password@orawest2:/w2sigb" -b orawest2 -d w2sigb -t w2sigc -y cohesity -v ora_sbt -f dup-set-w2sigc.ora
### duplidate PDB database when sbt library is in lib directory under the script directory
- ./duplicate-ora-coh-sbt.bash -r "user/password@orawest2:/cohcdbb" -b orawest2 -d cohcdbb -t cohcdbc -c orapdb1 -e orapdb1c -y cohesity -v ora_sbt -f dup-set-cohcdbc.ora
  
## duplicate exmaple from directory "orawest/orcl" under view "orasbt1" exmaple
The following example uses the directory "orawest/orcl" (host is orawest, the database is orcl) under view "orasbt1". You can mount the view to a Unix server to verify the backup files are in this directory.

### duplidate none CDB database example when sbt library is in lib directory under the script directory
- ./duplicate-ora-coh-sbt.bash -e "user/password@orawest2:/catalog" -b orawest2 -d w2sigb -t w2sigc -y cohesity -v ora_sbt/orawest/orcl -f dup-set-w2sigc.ora
### duplidate PDB database example when sbt library is in lib directory under the script directory
- ./duplicate-ora-coh-sbt.bash -r "user/password@orawest2:/cohcdbb" -b orawest2 -d cohcdbb -t cohcdbc -c orapdb1 -e orapdb1c -y cohesity -v ora_sbt/orawest/orcl -f dup-set-cohcdbc.ora
