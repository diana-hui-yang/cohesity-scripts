# Cohesity Oracle Backup Sample Script
***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

The bash script can be used to only generate RMAN script or generate/execute RMAN script to work with Cohesity platform. It first generates RMAN script and store it in a csv suffix file in \<bash script directory\>/log/\<oracle server name\> directory according to the inputs. When "\-w yes" is given as part of the input, only csv suffix file of RMAN script is generated. Without "\-w yes" input, the bash script will execute the RMAN script after generating the script. 
