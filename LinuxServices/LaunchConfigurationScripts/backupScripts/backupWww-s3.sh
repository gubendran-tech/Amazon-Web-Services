#!/bin/bash
#
# Author	Gubs
# Date		16 Aug 2016
#
# This script copies log files from the SCK Applications
# to an S3 bucket for further review.  This should simplify
# and reduce system load for backups.

#
# Variables
#

ADMIN="scksystems@kitchenbrains.com KBMonitoring@jeanmartin.com"
#ADMIN="gubs@jeanmartin.com"
TMPLOG=""
BKPLOG="/var/log/backup.log"
BUCKET="kb-sck-backups"
BKPDIR="/archive/${BUCKET}"
DATE=""
TIME=""
HOST=$(hostname)

export AWS_ACCESS_KEY_ID="AKIAIRD4CSH2JFR2RD3A"
export AWS_SECRET_ACCESS_KEY="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"

if [[ $HOST == *"staging"* ]]
then
  export AWS_DEFAULT_REGION="us-west-2"
else 
  export AWS_DEFAULT_REGION="us-east-1"
fi

#
# Log file locations
#
APACHE="/opt/apache/logs/"
HTTPD="/var/log/httpd/"

#############
# Functions #
#############

cleanup() {
    echo "Cleaning up."
    cat $TMPLOG >> $BKPLOG
    rm -f $TMPLOG
    exit $1
}

failed() {
    rmCacheDir
    mail -s "$HOST Backup Failed $2" $ADMIN < $TMPLOG
    cleanup 1	
}

getDate() {
    DATE="$(date +%Y%m%d)"
}

getTime() {
    TIME="$(date +%k%M)"
}

mkTmpFile() {
    TMPLOG=$(mktemp /tmp/backupXXX.log)
    status=$?
    if [ $status -ne 0 ]
    then
	logger -p error "Backup program cannot create log file"
	failed 2 "Could not create temp file.  This should not happen"
    fi
}

bkpLogs() {
    # see if there is a directory for this host
    if [ ! -d ${BKPDIR}/${HOST} ]
    then
	mkdir -p ${BKPDIR}/${HOST}
	status=$?
	if [ $status -ne 0 ]
	then
	    logger -p error "Failed to create hostname directory for backup"
	    failed 2 "Directory creation failed"
	fi
    fi
    # create directory for "today"
    mkdir -p ${BKPDIR}/${HOST}/${DATE}
    status=$?
    if [ $status -ne 0 ]
    then
	logger -p error "Failed to create hostname directory for backup"
	failed 2 "Directory creation failed"
	exit 1
    fi
    # Copy log files
    for logdir in ${APACHE} ${HTTPD}
    do
	cp -rp ${logdir}/* ${BKPDIR}/${HOST}/${DATE}
	status=$?
	if [ $status -ne 0 ]
	then
	    logger -p error "Copy of files in ${logdir} failed, please investigate"
	    failed 2 "Copy of files in ${logdir} failed"
	fi
    done
}

compressDir() {
    # see if there is a directory for this host
    if [ -d ${BKPDIR}/${HOST}/${DATE} ]
    then
        cd ${BKPDIR}/${HOST}/
	tar -cf ${DATE}.tgz ${DATE}
	status=$?
	if [ $status -ne 0 ]
	then
	    logger -p error "Failed to find directory for backup"
	    failed 2 "Directory missing and failed"
	fi
    fi
}

compressDirIntoS3() {
    # see if there is a directory for this host
    if [ -e ${BKPDIR}/${HOST}/${DATE}.tgz ]
    then
        aws s3 cp ${BKPDIR}/${HOST}/${DATE}.tgz s3://${BUCKET}/${HOST}/
	status=$?
	if [ $status -ne 0 ]
	then
	    logger -p error "Failed to copy directory into s3"
	    failed 2 "Failed to copy directory into s3"
	fi
    fi
}

rmCacheDir() {
    if [ -d ${BKPDIR}/${HOST} ]
    then
        rm -rf ${BKPDIR}/${HOST}
        status=$?
        if [ $status -ne 0 ]
        then
            logger -s -p error "could not clean up backup cache directory"
	    failed 2 "could not clean up cache"
        fi
    fi
}

#
# Main, This is where the real work gets done.
#

trap cleanup KILL TERM INT QUIT SIGKILL SIGINT

mkTmpFile
{

    getTime
    getDate
    echo "Backup of files on ${HOST} started on $DATE at $TIME"
    bkpLogs
    compressDir
    compressDirIntoS3
    rmCacheDir
    getTime
    getDate
    echo
    echo "Backup of files on ${HOST} finished on $DATE at $TIME"
    echo
    cat $TMPLOG >> $BKPLOG

} >> $TMPLOG

#
echo -e "${HOST}\t\tBackup\t ${HOST} backup sucessful\n"

# Update admin(s)
mail -s "$HOST Backup successfull" $ADMIN < $TMPLOG

# take out the trash
cleanup 0

# get out of "Dodge"
exit 0
