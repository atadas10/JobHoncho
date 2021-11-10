#!/bin/bash
# Description:  A script uto schedule DS Jobs.


SCRIPT_PATH=$1
CONNECTION=$SCRIPT_PATH/ConnectionDetails.conf
LOG=$(dirname $(readlink -f $0))/CreateBatch.log
CTRL_SCHEMA=ATADAS
INSTANCE_ID=WYDW


echo "*********************************************************************************"
echo "Usage : This script create new batch for ETL load" 
echo "" 
echo "Example: sh $0 SCRIPT_PATH" 
echo "*********************************************************************************"

if [ $# -ne 1 ] 
then 
echo " " 
echo " Please provide correct parameters" > $LOG
echo " " 
exit 1
fi 


if [ -f "$CONNECTION" ]; then 
	SERVER=`grep -w SERVER $CONNECTION | awk -F'=' '{printf "\n%s",$2}'`
	DSUsr=`grep -w DSUsr $CONNECTION | awk -F'=' '{printf "\n%s",$2}'`
	DBUSR=`grep -w DBUSR $CONNECTION | awk -F'=' '{printf "\n%s",$2}'`
	DBPWD=`grep -w DBPWD $CONNECTION | awk -F'=' '{printf "\n%s",$2}'`
	DBNAME=`grep -w DBNAME $CONNECTION | awk -F'=' '{printf "\n%s",$2}'`

else
	echo "$CONNECTION does notexist" > $LOG
	exit 1
fi

. /home/db2inst1/sqllib/db2profile
db2 connect to $DBNAME user $DBUSR using $DBPWD > /dev/null 2>&1

CurrentBatchStatus=`db2 -x "SELECT COUNT(1) FROM (SELECT BATCH_STATUS,ROW_NUMBER() OVER(ORDER BY BATCH_ID DESC) RN FROM ATADAS.CTRL_BATCH_NAME) WHERE RN=1 AND UPPER(BATCH_STATUS) <> 'COMPLETE'"` > /dev/null  2>&1

LAST_BATCH_TIME=`db2 -x "SELECT BATCH_START_TS FROM (SELECT BATCH_START_TS,ROW_NUMBER() OVER(ORDER BY BATCH_ID DESC) RN FROM ATADAS.CTRL_BATCH_NAME) WHERE RN=1"` > /dev/null  2>&1
CURR_BATCH_TIME=`date +"%F %T"`

if [ $CurrentBatchStatus = 0 ] 
then

db2 -x "INSERT INTO ATADAS.CTRL_BATCH_NAME(INSTANCE_ID,BATCH_START_TS,BATCH_STATUS) VALUES('$INSTANCE_ID','$CURR_BATCH_TIME','Started')" > /dev/null  2>&1
BATCH_ID=`db2 -x "SELECT MAX(BATCH_ID) FROM $CTRL_SCHEMA.CTRL_BATCH_NAME"` > /dev/null  2>&1
db2 -x "INSERT INTO $CTRL_SCHEMA.CTRL_BATCH_JOBS SELECT INSTANCE_ID,ROW_NUMBER() OVER() as JOB_PROCESS_ID,JOB_NAME,$BATCH_ID,NULL,NULL,CASE WHEN TRIM('$LAST_BATCH_TIME') = '' THEN '1900-01-01 00:00:00' ELSE '$LAST_BATCH_TIME' END,'$CURR_BATCH_TIME','New' FROM $CTRL_SCHEMA.CTRL_ETL_JOBS WHERE INCLUDE_IN_BATCH='Y'" > /dev/null  2>&1
db2 -x "COMMIT" > /dev/null  2>&1
echo $BATCH_ID > $SCRIPT_PATH/BATCH_FILE
echo "New batch $BATCH_ID created" > $LOG
exit 0
else
echo "Previous batch is not complete" > $LOG
exit 1
fi