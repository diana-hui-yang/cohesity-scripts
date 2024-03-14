# Cohesity Database backup/dump Sample Script
### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

The bash script in oracle/nfs, oracle/oim, oracle/sbt, and oracle/cohesityadapter folders can be used to generate RMAN commands only or generate/execute RMAN commands to work with Cohesity platform. When "\-w yes" is given as part of the input, it generates RMAN commands and stores it in a csv suffix file in \<bash script directory\>/log/\<oracle server name\> directory according to the inputs. Without "\-w yes" input, the bash script will execute the RMAN commands after generating the RMAN commands. 

The bash script in oracle/datapump folders can be used to generate Oracle export commands only or generate/execute Oracle export commands to work with Cohesity platform. When "\-w yes" is given as part of the input, it generates Oracle export commands and stores it in a csv suffix file in \<bash script directory\>/log/\<oracle server name\> directory according to the inputs. Without "\-w yes" input, the bash script will execute the Oracle export commands after generating the Oracle export commands. 

The bash script in sybase folders can be used to generate Sybase dump commands only or generate/executeSybase dump commands to work with Cohesity platform. When "\-w yes" is given as part of the input, it generates Sybase dump commands and stores it in a csv suffix file in \<bash script directory\>/log/\sybase server name\> directory according to the inputs. Without "\-w yes" input, the bash script will execute the Sybase dump commands after generating the Sybase dump commands. 

The bash script in db2 folders can be used to generate DB2 backup commands only or generate/executeSybase backup commands to work with Cohesity NFS mount. When "\-w yes" is given as part of the input, it generates DB2 backup commands and stores it in a csv suffix file in \<bash script directory\>/log/\DN2 server name\> directory according to the inputs. Without "\-w yes" input, the bash script will execute the DB2 backup commands after generating the DB2 backup commands. 


