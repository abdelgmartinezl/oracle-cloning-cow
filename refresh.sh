#!/bin/bash

# AUTHOR: Abdel Martinez (Solusoft)
# VERSION: 1.0
# DATE: July 16, 2015
# FILE: refresh.sh
# DESCRIPTION: Refresh environments based on their COW clone.

start=`date +%s`

# LIST OF VARIABLES:
# Environment name, example: PARIS
echo -n "Enter the environment name: "
read envname
envname=`echo $envname | awk '{print toupper($0)}'`
# Base filesystem, example: /u800
echo -n "Enter the base filesystem: "
read basefs

# Set the old environment name (lowercase)
envnamelc=`echo $envname | perl -ne 'print lc'`

# Set the new environment name (uppercase)
if [ ${#envname} -lt 5 ] ; then
  newname=$envname"PSU"
else
  newname=`echo ${envname:0:5}`"PSU"
fi
newname=`echo $newname | awk '{print toupper($0)}'`

# Set the new environment name (lowercase)
newnamelc=`echo $newname | perl -ne 'print lc'`

# Set the new base directory name
homedir=`echo ${basefs/c/u}`

clear
echo "ACP - ENVIRONMENT REFRESH"
echo "-------------------------"
echo "User: `whoami`"
echo "Environment: $envname"
echo "Date: `date`"
echo

# Create directory stucture using root
echo "Please introduce root password: "
su root -c "mkdir -p $homedir; cd $homedir; ln -s $basefs/$envnamelc .; ln -s $basefs/oradata .; chown -R oracle:dba $envnamelc; chown -R oracle:dba oradata; cd /u011/app/oracle/admin; mkdir -p $newnamelc/{adump,bdump,cdump,udump}; chown -R oracle:dba $newnamelc; mkdir -p $envnamelc/{adump,bdump,cdump,udump}; chown -R oracle:dba $envnamelc"
echo
echo "Directory structure created.........[OK]"

# Load environment variables
cd /u011/app/oracle
ln -s $homedir"/"$envnamelc"/home/ora/"$envname".env" $newname".env"
source ./$newname.env
echo "Environment variables loaded........[OK]"

# Disable all network operations
cd $ORACLE_HOME/network
mv admin admin.old
echo "Disable network operations..........[OK]"

# Validate if startup with pfile or spfile
cd $ORACLE_HOME/dbs
if [ -e "init"$envname".ora" ] ; then
  initfile = $ORACLE_HOME"/dbs/init"$envname".ora"
  echo -e 'connect / as sysdba\nstartup pfile="$initfile"\nquit'| sqlplus /nolog
  echo "Database started using pfile......[OK]"
elif [ -e "init"$envnamelc".ora" ] ; then
  initfile = $ORACLE_HOME"/dbs/init"$envnamelc".ora"
  echo -e 'connect / as sysdba\nstartup pfile="$initfile"\nquit'| sqlplus /nolog
  echo "Database started using pfile......[OK]"
else
  echo -e 'connect / as sysdba\nstartup\nquit'| sqlplus /nolog
  echo "Database started using spfile.....[OK]"
fi

# Validate if database is up
RETVAL=`sqlplus -silent / as sysdba <<EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT 'Alive' FROM dual;
EXIT;
EOF`
if [ "$RETVAL" = "Alive" ]; then
    echo -e 'connect / as sysdba\nalter system switch logfile;\nalter system switch logfile;\nquit'| sqlplus /nolog
    echo "Database is up and running........[OK]"
else
    echo "ERROR: There was an issue starting the database instance. Please review the logs."
fi


# REVIEW : Validate if logfile switch was done
alert_log=/u011/app/oracle/admin/$ORACLE_SID/bdump/alert_$ORACLE_SID.log
grep switch $alert_log > /dev/null
if [ $? = 0 ] ; then
  echo "The log switch were successful."
else
  echo "There were issues. Contact administrator."
  exit 5
fi

# Disable dataguard
echo -e "connect / as sysdba\nalter system set log_archive_dest_2='';\nalter system set fal_server='';\nquit"| sqlplus /nolog
echo -e "connect / as sysdba\nalter system set log_archive_config='SEND, RECEIVE, NODG_CONFIG';\nalter system set fal_client='';\nquit"| sqlplus /nolog
echo "Dataguard disabled..................[OK]"

# Disable archivelog if enabled
RETVAL=`sqlplus -silent / as sysdba <<EOF
set pages 0 feedback off verify off heading off echo off
@logmode.sql
exit;
EOF`
if [ "$RETVAL" = "ARCHIVELOG" ]; then
  echo -e 'connect / as sysdba\nshutdown immediate\nstartup mount\nalter database archivelog\nalter database open\nquit'| sqlplus /nolog
  echo "Archivelog disabled...............[OK]"
fi

# Create updated pfile/spfile
cd $ORACLE_HOME/dbs
if [ -e "init"$envname".ora" ] ; then
  echo -e 'connect / as sysdba\ncreate spfile from pfile\nquit'| sqlplus /nolog
  echo "Update spfile/pfile...............[OK]"
elif [ -e "init"$envnamelc".ora" ] ; then
  echo -e 'connect / as sysdba\ncreate spfile from pfile\nquit'| sqlplus /nolog
  echo "Update spfile/pfile...............[OK]"
else
  initfile=$ORACLE_HOME"/dbs/init"$envname".ora"
  echo "create pfile='"$initfile"' from spfile;" | $ORACLE_HOME/bin/sqlplus -S "/ as sysdba"
  echo "Update pfile/spfile...............[OK]"
fi

# Update SYS, SYSTEM and DBSNMP passwords
echo -e 'connect / as sysdba\nalter user sys identified by "Quw20xW9-P.x";\nquit'| sqlplus /nolog
echo -e 'connect / as sysdba\nalter user system identified by "Quw20xW9-P.x";\nquit'| sqlplus /nolog
echo -e 'connect / as sysdba\nalter user dbsnmp identified by "Quw20xW9-P.x";\nshutdown immediate\nstartup mount\nquit'| sqlplus /nolog
echo "Update passwords....................[OK]"

# Change database name
`nid TARGET=SYS/Quw20xW9-P.x DBNAME=$newname<< EOF
y
EOF`
echo "Database name changed...............[OK]"

# Create new password file
cd $ORACLE_HOME/dbs
orapwd file=orapw$newname password=Quw20xW9-P.x
echo "Password file created...............[OK]"

# Create base init file for new environment
newinit=$ORACLE_HOME"/dbs/init"$newname".ora"
echo -e "startup nomount\nalter system set db_name="$newname" scope=spfile;\nshutdown immediate\nquit" | $ORACLE_HOME/bin/sqlplus -S "/ as sysdba"
echo -e "startup mount\ncreate pfile='"$newinit"' from spfile;\nquit" | $ORACLE_HOME/bin/sqlplus -S "/ as sysdba"
echo "Base init file created..............[OK]"

# Replace old env name with the new env name
perl -pi -e 's/$envname/$newname/g' $ORACLE_HOME/dbs/init$newname.ora
echo "Name replacement in init file.......[OK]"

# Shutdown old database instance
echo -e 'connect / as sysdba\nshutdown immediate\nquit'| sqlplus /nolog
echo "Shutdown of old database instance...[OK]"

# Startup new database instance
export ORACLE_SID=$newname
echo -e "connect / as sysdba\nstartup mount pfile='"$newinit"';\nalter database set standby database to maximize performance;\nalter database open resetlogs;\ncreate spfile from pfile;\nquit"| sqlplus /nolog
echo "Startup of new database instance....[OK]"

# Re-enable archivelog, if previously enabled
if [ "$RETVAL" = "ARCHIVELOG" ]; then
  echo -e 'connect / as sysdba\nshutdown immediate\nstartup mount\nalter database archivelog\nalter database open\nquit'| sqlplus /nolog
  echo "Archivelog re-enabled.............[OK]"
else
  echo "The database is not in archivelog...."
fi

# Enable database listener
cd $ORACLE_HOME/network
cp -R /stage/solusoft/templates/admin .
echo -n "Enter the listener port number: "
read portnumber
perl -pi -e 's/9999/'$portnumber'/g' admin/listener.ora
perl -pi -e 's/9999/'$portnumber'/g' admin/tnsnames.ora
perl -pi -e 's/CHANGEME/'$newname'/g' admin/listener.ora
perl -pi -e 's/CHANGEME/'$newname'/g' admin/tnsnames.ora
lsnrctl start $newname
echo "Database listener started...........[OK]"

# Restart database
echo -e 'connect / as sysdba\nshutdown immediate\nstartup\nquit'| sqlplus /nolog
echo "Database restarted..................[OK]"

# Edit env file
cd /u011/app/oracle
perl -pi -e 's/'$envname'/'$newname'/g' $newname.env
source ./$newname.env
echo "Environment file updated............[OK]"

# Add the Oracle Home to the central inventory
if [ grep -Fxq "" $ORACLE_HOME/oraInst.loc ] ; then
  cd $ORACLE_HOME/oui/bin
  ./runInstaller -silent -attachHome -invPtrLoc /var/opt/oracle/oraInst.loc ORACLE_HOME=$ORACLE_HOME ORACLE_HOME_NAME="db_"$newnamelc"_u200_"$envnamelc"_db_11_2_0_3"
else
  perl -i -pe 'if ($. == 1) { s/.*/"inventory_loc=/u012/oracle/oraInventory"/; }' $ORACLE_HOME/oraInst.loc
  cd $ORACLE_HOME/oui/bin
  ./runInstaller -silent -attachHome -invPtrLoc /var/opt/oracle/oraInst.loc ORACLE_HOME=$ORACLE_HOME ORACLE_HOME_NAME="db_"$newnamelc"_u200_"$envnamelc"_db_11_2_0_3"
fi
echo "Oracle Home added to inventory......[OK]"

end=`date +%s`
runtime=$((end-start))
echo
echo "Time elapsed: $runtime seconds"
echo "Done!"
