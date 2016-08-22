#!/bin/bash

env=$1
instanceId=$2
if [ $env = 'prd' ] ; then
   alarmAction="arn:aws:sns:us-east-1:659149615316:api_status_alerts"
else 
   alarmAction="arn:aws:sns:us-west-2:659149615316:api_status_alerts"
fi

# CloudWatch Metric Alarm for CPU
aws cloudwatch put-metric-alarm --alarm-name ${instanceId}-cpu-mon --alarm-description "Alarm when CPU exceeds 80%" --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 300 --threshold 80 --comparison-operator GreaterThanThreshold  --dimensions  Name=InstanceId,Value=${instanceId}  --evaluation-periods 2 --alarm-actions ${alarmAction} --unit Percent

aws ec2 monitor-instances --instance-ids ${instanceId}

#change the alarm state 
#aws cloudwatch set-alarm-state  --alarm-name cpu-mon --state-reason "initializing" --state-value ALARM

# Delete Alarm by names 
#aws cloudwatch delete-alarms --alarm-name "Prod SFTP Server CPU Utilization"
