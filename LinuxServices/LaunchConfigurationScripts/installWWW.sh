#!/bin/bash

export AWS_ACCESS_KEY_ID="AKIAIRD4CSH2JFR2RD3A"
export AWS_SECRET_ACCESS_KEY="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"

env=$1
if [[ $env == "prd" ]] ; then
   export AWS_DEFAULT_REGION="us-east-1"
   alarmAction="arn:aws:sns:us-east-1:659149615316:api_status_alerts"
else
   export AWS_DEFAULT_REGION="us-west-2"
   alarmAction="arn:aws:sns:us-west-2:659149615316:api_status_alerts"
fi

#############
# Functions #
#############
failed() {
    if [ "$1" -ne 0 ] ; then
        echo -e "\t$2 failed. Exiting." >> $tmpLog
                mail -s "$HOSTNAME upgrade failed" $email < $tmpLog
                cleanup $1
    fi
    echo -e "\t$2 Done" >> $tmpLog
}
 
cleanup() {
    echo in clean up
    cat $tmpLog >> $log
    rm -rf $tmpLog
    exit $1
}

email="kbmonitoring@jeanmartin.com,scksystems@fastinc.com"
tmpLog="/tmp/wwwinstall.log"
log="/var/log/wwwinstall.log"
accessKeyId=$AWS_ACCESS_KEY_ID
accessSecretAccessKey=$AWS_SECRET_ACCESS_KEY
awsRegion=$AWS_DEFAULT_REGION
loadBalancerName="wwwELBinternal"
downloadFiles="/opt/"
httpdWWWFolder="apache"
httpdWWWUser="jboss"
sckBuildHost="75.127.245.92   sckbuild        sckbuild.fastinc.com"
messagingHost="10.0.0.21       messaging       messaging.staging.mysck.net"
backupScript="backupWww-s3.sh"
backupScheduler="backupWWW"
builduid=sckadmin
buildserv=sckbuild.fastinc.com

trap cleanup KILL TERM INT QUIT SIGKILL SIGINT
{
    # Install required libraries
    yum -y install libXp.x86_64 elfutils-devel.x86_64 elfutils-libelf-devel.x86_64 krb5-libs.i686 nss-pam-ldapd.i686 ksh-*.x86_64 compat-libstdc++-*.i686 nss-pam-ldapd.i686 libstdc++-*.i686 
    
    failed $? "yum install required libraries failed"

    # Install httpd
    yum -y install httpd
    failed $? "yum install httpd failed"

    chkconfig --level 234 httpd on

    # Install ssl
    yum -y install mod_ssl
    failed $? "yum install mod_ssl failed"
    
    # Update .bashrc
    echo "export AWS_ACCESS_KEY_ID=\"${accessKeyId}\""  >> ~/.bashrc
    echo "export AWS_SECRET_ACCESS_KEY=\"${accessSecretAccessKey}\""  >> ~/.bashrc
    echo "export AWS_DEFAULT_REGION=\"${awsRegion}\""  >> ~/.bashrc
    echo "export HISTSIZE=\"\"" >> ~/.bashrc
    source ~/.bashrc

    #Create jboss user
    groupadd ${httpdWWWUser}
    useradd -g ${httpdWWWUser} ${httpdWWWUser}

    # enable port for http and https
    iptables -F
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    service iptables save
    service iptables restart
    
    failed $? "iptables failed enabling"
    
    # httpd configuration and start
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/www-httpd-conf/httpd.conf ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/www-httpd-conf/proxy_ajp.conf ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/www-httpd-conf/ssl.conf ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/www-httpd-conf/index.html ${downloadFiles}
    
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/httpd-conf/ssl/ca-bundle.crt ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/httpd-conf/ssl/wildcard.key ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/httpd-conf/ssl/wildmysck.crt ${downloadFiles}
    
    mv /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf-orig
    mv /etc/httpd/conf.d/proxy_ajp.conf /etc/httpd/conf.d/proxy_ajp.conf-orig
    mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf-orig
    mv /var/www/html/index.html /var/www/html/index.html-orig
    
    mv httpd.conf /etc/httpd/conf/
    mv proxy_ajp.conf /etc/httpd/conf.d/
    mv ssl.conf /etc/httpd/conf.d/
    mv index.html /var/www/html/
    
    mkdir /etc/httpd/conf/ssl
    mv ca-bundle.crt wildcard.key wildmysck.crt /etc/httpd/conf/ssl/
    
    # Download apache folder specific to mysck build
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/www-httpd-conf/${httpdWWWFolder}.zip ${downloadFiles}
 
    # Unzip
    unzip ${downloadFiles}/${httpdWWWFolder}.zip
    rm -fr ${httpdWWWFolder}.zip
    chown -R jboss.jboss $downloadFiles/${httpdWWWFolder}

    echo 5am1am > /root/rsyncd.passwd
    chmod 600 /root/rsyncd.passwd

    # Rsync the upgrade file
    rsync -avhclz --stats --progress --password-file /root/rsyncd.passwd ${builduid}@${buildserv}::latestqa/aboveStore/upgrade/qastaging/upgradesckui.sh ${downloadFiles}
    
    chmod +x ${downloadFiles}/upgradesckui.sh
    ${downloadFiles}/upgradesckui.sh
    
    # httpd start
    /etc/init.d/httpd start

    # Copy the backup script for www
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/LaunchConfigurationScripts/backupScripts/${backupScript} ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/LaunchConfigurationScripts/backupScripts/${backupScheduler} ${downloadFiles}
    mv ${downloadFiles}/${backupScript} /usr/local/sbin/${backupScript}
    mv ${downloadFiles}/${backupScheduler} /etc/cron.d/${backupScheduler}

    chmod 0644 /etc/cron.d/${backupScheduler}

    chmod +x /usr/local/sbin/${backupScript}
 
    # Copy cloudWatch modified perl script to support monitor pid
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/CloudWatch/mon-put-instance-data-modified.pl ${downloadFiles}
    mv /opt/aws-scripts-mon/mon-put-instance-data.pl /opt/aws-scripts-mon/mon-put-instance-data.pl-orig
    mv mon-put-instance-data-modified.pl /opt/aws-scripts-mon/mon-put-instance-data.pl
    chmod 755 /opt/aws-scripts-mon/mon-put-instance-data.pl
    
    # Copy cloudWatch for apache and tomcat too
    #/usr/local/bin/aws s3 cp s3://kb-sck-softwares/CloudWatch/cloudWatchCron-httpd-tomcat ${downloadFiles}
    #mv cloudWatchCron-httpd-tomcat /etc/cron.d/cloudWatch 
    
    instanceId=$(curl http://169.254.169.254/latest/meta-data/instance-id)
    /usr/local/bin/aws elb register-instances-with-load-balancer --load-balancer-name ${loadBalancerName} --instances ${instanceId}
    failed $? "adding elb"

    # Enable Detailed Monitoring Metrics
    /usr/local/bin/aws ec2 monitor-instances --instance-ids ${instanceId}

    #Add cloudWatch Metric Alarm 
    /usr/local/bin/aws cloudwatch put-metric-alarm --alarm-name ${instanceId}-cpu-mon --alarm-description "Alarm when CPU exceeds 80%" --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 300 --threshold 80 --comparison-operator GreaterThanThreshold  --dimensions  Name=InstanceId,Value=${instanceId}  --evaluation-periods 2 --alarm-actions ${alarmAction} --unit Percent
    failed $? "Cloudwatch not added" 
    
   # Add server into host 
   echo "${messagingHost}" >> /etc/hosts
   echo "${sckBuildHost}" >> /etc/hosts

} >> $tmpLog

echo "Completed at $(date)" | mail -s "$HOSTNAME - WWW installed successfully in Instance: ${instanceId}" 
cat $tmpLog >> $log
cleanup 0
exit 0
