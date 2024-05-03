### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***


## Duplicate scripts Description
This bash script utilize RMAN duplicate command to duplicate, or clone, a database from the backup taken by using backup-ora-coh-sbt-23.bash script if it is Oracle database on Linux. It should be used in conjunction with a Cohesity ZDLRA-type view. The Cohesity ZDLRA-type view enables Cohesity to manage Oracle backup retention through a policy defined on the Cohesity platform. When using point-in-time like "2020-08-23 11:30:00', it is the timezone on the source server, not the target server if there is a timezone difference. 
