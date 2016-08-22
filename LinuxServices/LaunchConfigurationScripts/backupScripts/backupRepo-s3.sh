#!/bin/bash

# List folders here that may or may not be under base path.
# If folder isn't under base path we do nothing.
# If it exists we back it up to S3.
#
export AWS_ACCESS_KEY_ID="AKIAIRD4CSH2JFR2RD3A"
export AWS_SECRET_ACCESS_KEY="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"
export AWS_DEFAULT_REGION="us-east-1"

declare -a folders=(
  "sonatype-work"
)

BASE_PATH="/opt/"
BUCKET="kb-sck-backups/prd.repo.mysck.internal"
#pastDate=$(date  --date="3 days ago" +"%Y%m%d")


for FOLDER in "${folders[@]}"
do
  if [ -d ${BASE_PATH}/${FOLDER} ] ; then
    cd ${BASE_PATH}
    gzipFolder=${FOLDER}-$(date '+%Y%m%d').tgz
    #removeS3Folder=${FOLDER}-${pastDate}.tgz
    tar -cf $gzipFolder ${FOLDER}
    aws s3 cp $gzipFolder s3://${BUCKET}/${gzipFolder}
    rm -fr $gzipFolder
    # If ls true then execute remove
    #aws s3 ls s3://${BUCKET}/${removeS3Folder} && aws s3 rm s3://${BUCKET}/${removeS3Folder}
  fi
done
