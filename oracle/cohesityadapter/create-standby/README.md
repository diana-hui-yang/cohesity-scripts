### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***


## Description
This script will instantiate an Oracle Data Guard Physical Standby from a Cohesity backup. A Cohesity Oracle recovery view needs to be created first. When running the script without any options, it displays the script usage. When using the "-w yes" parameter, the script builds a softlink of backup files in NFS mounts of the Cohesity view to a single directory under /tmp/orarestore and creates RMAN commands without executing them.
