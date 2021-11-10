#!/bin/bash
# Description:  A script uto schedule DS Jobs.


SCRIPT_PATH=$1  #/data/WY_WINGS/Scripts
CURR_PATH=$(dirname $(readlink -f $0))
CONNECTION=$CURR_PATH/ConnectionDetails.conf
CTRL_SCHEMA=ATADAS
LOG=$CURR_PATH/JobHoncho.Log
BATCH_ID=`cat $CURR_PATH/BATCH_FILE`

echo "*********************************************************************************"
echo "Usage : This script check for runnable jobs and trigger accordingly" 
echo "" 
echo "Example: sh $0 JOB_NAME SCRIPT_PATH PARAM_FILE_PATH PARAM_FILE_NAME" 
echo "*********************************************************************************"

if [ $# -ne 1 ] 
then 
echo " " 
echo " Please provide correct parameters for $0" >> $LOG
echo " " 
exit 1
fi 


if [ -f "$CONNECTION" ]; then 
	SERVER=`grep -w SERVER $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	DSUsr=`grep -w DSUsr $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	DBUSR=`grep -w DBUSR $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	DBPWD=`grep -w DBPWD $CONNECTION | awk -F'=' '{printf "%s",$2}'`
	DBNAME=`grep -w DBNAME $CONNECTION | awk -F'=' '{printf "%s",$2}'`

else
	echo "$CONNECTION does not exist for $0 " >> $LOG
	exit 1
fi

. /home/db2inst1/sqllib/db2profile
db2 connect to $DBNAME user $DBUSR using $DBPWD > /dev/null 2>&1

CurrentBatchStatus=`db2 -x "SELECT CAST(CASE UPPER(BATCH_STATUS) WHEN 'COMPLETE' THEN 0 ELSE 1 END AS INTEGER) FROM (SELECT BATCH_STATUS,ROW_NUMBER() OVER(ORDER BY BATCH_ID DESC) RN FROM $CTRL_SCHEMA.CTRL_BATCH_NAME) WHERE RN=1"` > /dev/null  2>&1

if [ $CurrentBatchStatus = 0 ] 
then
echo "No batch is running" > $LOG
exit 0
fi


while [ 1 ]
do
db2 -x "SELECT JOB_NAME FROM $CTRL_SCHEMA.CTRL_BATCH_JOBS WHERE UPPER(JOB_STATUS) = 'NEW' AND BATCH_ID=$BATCH_ID" | while read JobName
	do 

#JobName=`db2 -x "SELECT JOB_NAME FROM (SELECT JOB_NAME,JOB_STATUS,ROW_NUMBER() OVER(ORDER BY JOB_PROCESS_ID ASC) RN FROM $CTRL_SCHEMA.CTRL_BATCH_JOBS WHERE UPPER(JOB_STATUS) = 'NEW') WHERE RN = 1"` > /dev/null  2>&1 ##Job name to execute


# echo ""
# echo "Job name is $JobName"
# echo ""

db2 connect to $DBNAME user $DBUSR using $DBPWD > /dev/null 2>&1
IsRunnable=`db2 -x "SELECT $CTRL_SCHEMA.UDF_JOB_RUNNABLE('$JobName',$BATCH_ID) FROM SYSIBM.DUAL"` > /dev/null  2>&1

#echo "IsRunnable: $IsRunnable"

	if [ $IsRunnable = 0 ]  # Start Block 2
	then 
	ssh $DSUsr@$SERVER "rm -f $SCRIPT_PATH/$JobName.param;touch $SCRIPT_PATH/$JobName.param"
	db2 -x "SELECT PARAM_NAME,PARAM_VALUE FROM $CTRL_SCHEMA.CTRL_PARAMETERS WHERE UPPER(JOB_NAME) = '$JobName'" | while read parameter value
	do 
	ssh $DSUsr@$SERVER  "echo "$parameter=$value" >> $SCRIPT_PATH/$JobName.param"
	done
	
	db2 -x "SELECT EXTRACT_DATE_FROM,EXTRACT_DATE_TO FROM $CTRL_SCHEMA.CTRL_BATCH_JOBS WHERE UPPER(JOB_NAME) = '$JobName'" | while read LastRunDate,RunDate
	do 
	ssh $DSUsr@$SERVER  "echo "LastRunDate=$LastRunDate" >> $SCRIPT_PATH/$JobName.param; echo "RunDate=$RunDate" >> $SCRIPT_PATH/$JobName.param"
	done
	
	echo "Running Job $JobName"
	#sh $SCRIPT_PATH/RunETLJob.sh '1st' $SCRIPT_PATH $JobName $SCRIPT_PATH &
	
	#Run Job in DS Server
	ssh $DSUsr@$SERVER "$SCRIPT_PATH/RunETLJob.sh $JobName $SCRIPT_PATH $SCRIPT_PATH $BATCH_ID" & > /dev/null  2>&1 
	db2 -x "UPDATE $CTRL_SCHEMA.CTRL_BATCH_JOBS SET JOB_STATUS = 'Running',JOB_START_TS=CURRENT_TIMESTAMP WHERE JOB_NAME = '$JobName' AND BATCH_ID=$BATCH_ID" > /dev/null  2>&1
	fi 	# End Block 2

done

	JobStatus=`db2 -x "SELECT COUNT(DISTINCT JOB_STATUS) FROM $CTRL_SCHEMA.CTRL_BATCH_JOBS WHERE UPPER(JOB_STATUS) = 'RUNNING' AND BATCH_ID=$BATCH_ID"` > /dev/null  2>&1

	while [ $JobStatus != 0 ] 
	do
		#echo " " 
		#echo " Sleeping for 5 mints as jobs are in running state"
		sleep 5s
		#echo " " 
	JobStatus=`db2 -x "SELECT COUNT(DISTINCT JOB_STATUS) FROM $CTRL_SCHEMA.CTRL_BATCH_JOBS WHERE UPPER(JOB_STATUS) = 'RUNNING' AND BATCH_ID=$BATCH_ID"` > /dev/null  2>&1
	done
	
	JobStatus=`db2 -x "SELECT COUNT(DISTINCT JOB_STATUS) FROM $CTRL_SCHEMA.CTRL_BATCH_JOBS WHERE UPPER(JOB_STATUS) = 'ABORT' AND BATCH_ID=$BATCH_ID"` > /dev/null  2>&1


	if [ $JobStatus != 0 ]  # Start Block1
	then
	sleep 1s
	#echo " Job in abort state"
	fi  # End Block1

	JobStatus=`db2 -x "SELECT COUNT(1)  FROM $CTRL_SCHEMA.CTRL_BATCH_JOBS WHERE UPPER(JOB_STATUS) <> 'COMPLETE' AND BATCH_ID=$BATCH_ID"` > /dev/null  2>&1	
	if [ $JobStatus = 0 ]
	then
	echo "Batch success"
	db2 -x "UPDATE $CTRL_SCHEMA.CTRL_BATCH_NAME SET BATCH_STATUS = 'Complete',BATCH_END_TS=CURRENT_TIMESTAMP WHERE BATCH_ID=$BATCH_ID" > /dev/null  2>&1
	db2 -x "commit" > /dev/null  2>&1
	exit 0
	fi 

done