#!/bin/bash

JobName=$1
ParamFile=$1.param
ParamFilePath=$2 #/home/developer1/Atanu/Batchman
SCRIPT_PATH=$3 ##/home/developer1/Atanu/Batchman
BATCH_ID=$4
LOG=$(dirname $(readlink -f $0))/RunETLJob.log
CTRL_SCHEMA=ATADAS

echo "*********************************************************************************"
echo "Usage : This script execute $JobName" 
echo "" 
echo "Example: sh $0 JOB_NAME PARAM_FILE_PATH PARAM_FILE_NAME SCRIPT_PATH" 
echo "*********************************************************************************"

if [ $# -ne 4 ] 
then 
echo " " 
echo " Please provide correct parameters" 
echo " " 
exit 
fi 


CONNECTION=$SCRIPT_PATH/ConnectionDetails.conf

if [ -f "$CONNECTION" ]; then 
	PROJECT=`grep -w PROJECT $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	DOMAIN=`grep -w DOMAIN $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	SERVER=`grep -w SERVER $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	DSUsr=`grep -w DSUsr $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	DSPwd=`grep -w DSPwd $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	DBSERVER=`grep -w DBSERVER $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	DBUSR=`grep -w DBUSR $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	DBPWD=`grep -w DBPWD $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	DBNAME=`grep -w DBNAME $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	
else
	echo "$CONNECTION does notexist"
	exit
fi

###################################################
#
# Trigger Job to load table.
#
###################################################

DSHOME_PATH=`grep -w DSHOME $CONNECTION | awk -F'=' '{printf "\n%s",$2}'`
cd $DSHOME_PATH
. ./dsenv > /dev/null 2>&1


DSJobStatus=`$DSHOME/bin/dsjob -domain $DOMAIN -server $SERVER -user $DSUsr -password $DSPwd -jobinfo $PROJECT $JobName` > /dev/null  2>&1

Jobstatus=`echo $DSJobStatus grep "Job Status" | cut -f2 -d '('|cut -f1 -d ')'` > /dev/null 2>&1


#Check $JobStatus
if [ $Jobstatus -eq 3 ]
then

# "ETL Job $JobName in Aborted state"

$DSHOME/bin/dsjob -domain $DOMAIN -server $SERVER -user $DSUsr -password $DSPwd -run -warn 0 -mode RESET -wait -jobstatus $PROJECT $JobName > /dev/null  2>&1
  
 
  sleep 1m

  $DSHOME/bin/dsjob -domain $DOMAIN -server $SERVER -user $DSUsr -password $DSPwd -run -wait -jobstatus -paramfile $ParamFilePath/$ParamFile $PROJECT $JobName > /dev/null  2>&1
RETURNCODE=$? 
else

# echo "ETL Job $JobName Not in Aborted state"

$DSHOME/bin/dsjob -domain $DOMAIN -server $SERVER -user $DSUsr -password $DSPwd -run -wait -jobstatus -paramfile $ParamFilePath/$ParamFile $PROJECT $JobName > /dev/null  2>&1

#$DSHOME/bin/dsjob -user $DSUsr -password $DSPwd -run -warn 0 -wait -jobstatus -paramfile $ParamFilePath/$ParamFile $PROJECT $JobName > /dev/null  2>&1
RETURNCODE=$? 
fi

###################################################
#
# Print table load status
#
###################################################

if [  $RETURNCODE = 1 -o $RETURNCODE = 2  ]
then 

	echo "ETL job $JobName completed successfully" > $LOG
	
	ssh $DBUSR@USSLTC7496v.dev.sltc.com ". /home/db2inst1/sqllib/db2profile; db2 connect to $DBNAME user $DBUSR using $DBPWD ;db2 -x \"UPDATE $CTRL_SCHEMA.CTRL_BATCH_JOBS SET JOB_STATUS = 'Complete',JOB_END_TS = CURRENT_TIMESTAMP WHERE JOB_NAME = '$JobName' AND BATCH_ID=$BATCH_ID\""
	
	else
	echo ""
	echo "ETL job $JobName abort with Return Code :" $RETURNCODE 
	
	ssh $DBUSR@USSLTC7496v.dev.sltc.com ". /home/db2inst1/sqllib/db2profile;db2 connect to $DBNAME user $DBUSR using $DBPWD ;db2 -x \"UPDATE $CTRL_SCHEMA.CTRL_BATCH_JOBS SET JOB_STATUS = 'Abort' WHERE JOB_NAME = '$JobName' AND BATCH_ID=$BATCH_ID\""
fi