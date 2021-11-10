#!/bin/bash
# Description:  A wrapper script used to stop/start another script.

#--------------------------------------
# Define Global Environment Settings:
#--------------------------------------

# Name and location of a persistent PID file

SCRIPT_PATH=$(dirname $(readlink -f $0))
PIDFILE=$SCRIPT_PATH/PIDFILE
LOG=$SCRIPT_PATH/JobHoncho.Log
RUNAT=Mon11:30
DSServerPath=/home/developer1/Atanu/JobHoncho

#--------------------------------------
# Check command line option and run...
# Note that "myscript" should not
# provided by the user.
#--------------------------------------

case $1
in
    Start)
	
        # Print a message indicating the script has been started
        echo "Script has been started..." > $LOG
	
		BatchCompleteInd=0
		
        while true
        do	
		
			if [ $BatchCompleteInd != 1 -o `date +"%a%H:%M"` = $RUNAT  ] 
			then
			# sh JobHoncho.sh /home/developer1/Atanu/JobHoncho
			
			if [ `date +"%a%H:%M"` = $RUNAT ]
			then
			sh $SCRIPT_PATH/CreateBatch.sh $SCRIPT_PATH > /dev/null  2>&1
				
				if [ $? = 0 ] 
				then
				echo "New batch created as per schedule" >> $LOG
				fi
			sleep 60s
			
			fi
			
			echo "Started Job execution" >> $LOG
			sh $SCRIPT_PATH/JobHoncho.sh $DSServerPath >> $LOG
		
			if [ $? = 0 ] 
			then
            BatchCompleteInd=1
			fi
			fi
			
        done

    ;;

    Stop)
        # Read the process number into the variable called PID
        #read PID < $PIDFILE
		
		ps aux | grep JobHonchoDaemon.sh | grep -v grep | awk '{ print $2 }' > $PIDFILE
		ps aux | grep JobHoncho.sh | grep -v grep | awk '{ print $2 }' >> $PIDFILE
		
		DeamonPID=`head -1 $PIDFILE` > /dev/null  2>&1
		JobHonchoPID=`tail -1 $PIDFILE` > /dev/null  2>&1

		# Send a 'terminate' signal to process
        #kill $PID
		
		kill -9 $DeamonPID
		kill -9 $JobHonchoPID

        # Remove the PIDFILE
        rm -f $PIDFILE

        # Print a message indicating the script has been stopped
        echo "Script has been stopped..."
    ;;
	
	CreateBatch)
	
			sh $SCRIPT_PATH/CreateBatch.sh $SCRIPT_PATH >> $LOG
			
			if [ $? -eq 0 ]
			then
			BATCH_ID=`cat $SCRIPT_PATH/BATCH_FILE`
			echo ""
			echo "New batch $BATCH_ID created......."
			echo "Start the daemon........"
			exit 0
			else 
			echo "Batch not created. Check log : $SCRIPT_PATH/CreateBatch.log"
			fi
	;;
	
    *)
        # Print a "usage" message in case no arguments are supplied
        echo "Usage: $0 Start | Stop | CreateBatch"
    ;;
esac