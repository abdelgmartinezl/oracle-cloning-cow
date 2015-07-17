#!/bin/bash

# AUTHOR: Abdel Martinez (Solusoft)
# VERSION: 1.0
# DATE: July 16, 2015
# FILE: refresh.sh
# DESCRIPTION: Refresh environments based on their COW clone.

# LIST OF VARIABLES:
# $1: Environment name, example: PARIS
echo -n "Enter the environment name: "
read envname
# $2: Base filesystem, example: /u800
echo -n "Enter the base filesystem: "
read basefs

# Set the old environment name (lowercase)
envnamelc=`echo $envname | awk '{print tolower($0)}'`

# Set the new environment name (uppercase)
if [ ${#envname} -lt 5 ] ; then
  newname=$envname"PSU"
else
  newname=`echo ${envname:0:5}`"PSU"
fi
newname=`echo $newname | awk '{print toupper($0)}'`

# Set the new environment name (lowercase)
newnamelc=`echo $newname | awk '{print tolower($0)}'`

# Set the new base directory name
homedir=`echo ${basefs/c/u}`

clear
echo "ACP - ENVIRONMENT REFRESH"
echo "-------------------------"
echo "User: $USER"
echo "Environemnt: $envname"
echo "Date: `date`"
echo

# Create directory stucture using root
su root -c "mkdir -p $homedir; cd $homedir; ln -s $basefs/`echo $envname | awk '{print tolower($0)}'`; ln -s $basefs/oradata; chown -R oracle:dba `echo $envname | awk '{print tolower($0)}'`; chown -R oracle:dba oradata"

# Load environment variables
cd
ln -s $homedir"/"$envname"/home/ora/"$envname".env" $newname".env"
source ./$newname.env

# Disable all network operations
cd $ORACLE_HOME/network
mv admin admin.old

# Create dump directories
su root -c "cd /u011/app/oracle/admin; mkdir $newname; chown -R oracle:dba $newname"

# Validate if startup with pfile or spfile
cd $ORACLE_HOME/dbs
if [ -e "init"$envname".ora" ] ; then
  initfile = $ORACLE_HOME"/dbs/init"$envname".ora"
  `echo -e 'connect / as sysdba\nstartup pfile="$initfile"\nquit'| sqlplus /nolog`
elif [ -e "init"$envnamelc".ora" ] ; then
  initfile = $ORACLE_HOME"/dbs/init"$envnamelc".ora"
  `echo -e 'connect / as sysdba\nstartup pfile="$initfile"\nquit'| sqlplus /nolog`
else
  `echo -e 'connect / as sysdba\nstartup\nquit'| sqlplus /nolog`
fi

# Validate if database is up
check_stat=`ps -ef|grep $ORACLE_SID|grep pmon|wc -l`;
oracle_num=`expr $check_stat`
if [ $oracle_num -lt 1 ] ; then
  `echo -e 'connect / as sysdba\nalter system switch logfile;\nalter system switch logfile;\nquit'| sqlplus /nolog`
else
  echo "Hay un problema iniciando la instancia, favor validar."
  exit 5
fi

# Validate if logfile switch was done
alert_log=$ORACLE_BASE/diag/$ORACLE_SID/bdump/alert_$ORACLE_SID.log
grep checkpoint $alert_log > /dev/null
if [ $? = 0 ] ; then
  echo "The following checkpoints were found on $alert_log"
  grep ORA- $alert_log
else
  echo "There were issues. Contact administrator."
  exit 5
fi

# Disable dataguard
`echo -e 'connect / as sysdba\nalter system set log_archive_dest_2='';\nalter system set fal_server='';\nquit'| sqlplus /nolog`
`echo -e 'connect / as sysdba\nalter system set log_archive_config='SEND, RECEIVE, NODG_CONFIG';\nalter system set fal_client='';\nquit'| sqlplus /nolog`

# Disable archivelog if enabled
RETVAL=`sqlplus -silent / as sysdba <<EOF
set pages 0 feedback off verify off heading off echo off
@refp3.sql
exit;
EOF`
if [ "$RETVAL" = "ARCHIVELOG" ]; then
  `echo -e 'connect / as sysdba\nshutdown immediate\nstartup mount\nalter database archivelog\nalter database open\nquit'| sqlplus /nolog`
fi

# Create updated pfile/spfile
cd $ORACLE_HOME/dbs
if [ -e "init"$envname".ora" ] ; then
  `echo -e 'connect / as sysdba\ncreate spfile from pfile\nquit'| sqlplus /nolog`
elif [ -e "init"$envnamelc".ora" ] ; then
  `echo -e 'connect / as sysdba\ncreate spfile from pfile\nquit'| sqlplus /nolog`
else
  initfile = $ORACLE_HOME"/dbs/init"$envname".ora"
  `echo -e 'connect / as sysdba\ncreate pfile="$initfile" from spfile\nquit'| sqlplus /nolog`
fi

# Update SYS, SYSTEM and DBSNMP passwords
`echo -e 'connect / as sysdba\nalter user sys identified by "Quw20xW9-P.x";\nquit'| sqlplus /nolog`
`echo -e 'connect / as sysdba\nalter user system identified by "Quw20xW9-P.x";\nquit'| sqlplus /nolog`
`echo -e 'connect / as sysdba\nalter user dbsnmp identified by "Quw20xW9-P.x";\nshutdown immediate\nstartup mount\nquit'| sqlplus /nolog`

# Change database name
`nid TARGET=SYS/Quw20xW9-P.x DBNAME=$newname<< EOF
y
EOF`

# Create new password file
cd $ORACLE_HOME/dbs
orapwd file=orapw$newname password=Quw20xW9-P.x

# Create base init file for new environment
`echo -e 'connect / as sysdba\nstartup mount\ncreate pfile="$ORACLE_HOME/dbs/init$newname.ora" from spfile;\nquit'| sqlplus /nolog`

# Replace old env name with the new env name
perl -pi -e 's/$envname/$newname/g' $ORACLE_HOME/dbs/init$newname.ora

# Shutdown old database instance
`echo -e 'connect / as sysdba\nshutdown immediate\nquit'| sqlplus /nolog`

# Startup new database instance
export ORACLE_SID=$newname
`echo -e 'connect / as sysdba\nstartup mount pfile='$ORACLE_HOME/dbs/init$newname.ora';\nalter database set standby database to maximize performance;\nalter database open resetlogs;\ncreate spfile from pfile;\nquit'| sqlplus /nolog`

# Re-enable archivelog, if previously enabled
if [ "$RETVAL" = "ARCHIVELOG" ]; then
  `echo -e 'connect / as sysdba\nshutdown immediate\nstartup mount\nalter database archivelog\nalter database open\nquit'| sqlplus /nolog`
fi

# Enable database listener
cd $ORACLE_HOME/network
cp -R /stage/solusoft/templates/admin .
echo -n "Enter the listener port number: "
read portnumber
perl -pi -e 's/9999/$portnumber/g' admin/listener.ora
perl -pi -e 's/9999/$portnumber/g' admin/tnsnames.ora
lsnrctl start $newname

# Restart database
`echo -e 'connect / as sysdba\nshutdown immediate\nstartup\nquit'| sqlplus /nolog`

# Edit env file
cd /u011/app/oracle
perl -pi -e 's/$envname/$newname/g' $newname.env
source ./$newname.env

# Add the Oracle Home to the central inventory
if [ grep -Fxq "" $ORACLE_HOME/oraInst.loc ] ; then
  cd $ORACLE_HOME/oui/bin
  ./runInstaller -silent -attachHome -invPtrLoc /var/opt/oracle/oraInst.loc ORACLE_HOME=$ORACLE_HOME ORACLE_HOME_NAME="db_$newnamelc_u8120_$envnamelc_db_11_2_0_3"
else
  perl -i -pe 'if ($. == 1) { s/.*/"inventory_loc=/u012/oracle/oraInventory"/; }' $ORACLE_HOME/oraInst.loc
fi

echo
echo "Done!"
