# Cohesity Oracle Database backup/dump Sample Script
### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

The bash script in adapter, nfs, oim, and sbt folders can be used to generate RMAN commands only or generate/execute RMAN commands to work with Cohesity platform. When "\-w yes" is given as part of the input, it generates RMAN commands and stores it in a csv suffix file in \<bash script directory\>/log/\<oracle server name\> directory according to the inputs. Without "\-w yes" input, the bash script will execute the RMAN commands after generating the RMAN commands. 

The bash script in datapump folders can be used to generate Oracle export commands only or generate/execute Oracle export commands to work with Cohesity platform. When "\-w yes" is given as part of the input, it generates Oracle export commands and stores it in a csv suffix file in \<bash script directory\>/log/\<oracle server name\> directory according to the inputs. Without "\-w yes" input, the bash script will execute the Oracle export commands after generating the Oracle export commands. 

