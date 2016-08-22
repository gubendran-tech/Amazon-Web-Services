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
# functions #
#############
failed() {
        if [ "$1" -ne 0 ] ; then
                echo -e "\t$2 command failed. Exiting.";
                exit 1;
        fi
        echo -e "\t$2 Done. "
}

opttemp() {
    cd /opt
    rm -rf $opttempdir
    cd /opt
    mkdir -p $opttempdir
    cd $opttempdir
    failed $? "created $opttempdir"
}

cleanup() {
    echo in clean up
    rm -rf $opttempdir
    cat $tmpLog >> $log
    rm -rf $tmpLog
    exit $1
}

# Variables #
#############
wildflyarch=wildfly-9.0.2.Final.zip
wildflyarchdir=wildfly-9.0.2.Final
wildflydir=/opt/wildfly

alias cp='cp'
alias rm='rm'
alias mv='mv'

email="gubs@jeanmartin.com"
#email="kbmonitoring@jeanmartin.com,scksystems@fastinc.com"
tmpLog=/tmp/wildflyinstall.log
log=/var/log/wildflyinstall.log
builduid=sckadmin
buildserv=sckbuild
buildloc=latestqa
txdbname="mysck-stag"
dwdbname="mysckdw-stag"
dwdbmirrorip="10.0.0.22"
accessKeyId=$AWS_ACCESS_KEY_ID
accessSecretAccessKey=$AWS_SECRET_ACCESS_KEY
awsRegion=$AWS_DEFAULT_REGION
loadBalancerName="apielbinternal"
sckBuildIp="75.127.245.92"

trap cleanup KILL TERM INT QUIT SIGKILL SIGINT
{
    # Install required libraries
    yum -y install libXp.x86_64 elfutils-devel.x86_64 elfutils-libelf-devel.x86_64 krb5-libs.i686 nss-pam-ldapd.i686 ksh-*.x86_64 compat-libstdc++-*.i686 nss-pam-ldapd.i686 libstdc++-*.i686

    failed $? "yum install required libraries failed"

    if [ -z "$(grep "$dwdbmirrorip" /etc/hosts)" ] ; then
        echo "$dwdbmirrorip                     DataMartDB" >> /etc/hosts
        failed $? "writing DataMartDB to hosts file"
    else
        if [ -z "$(grep "DataMartDB" /etc/hosts)" ] ; then
               sed -i "s/\($dwdbmirrorip.*\)/\1 DataMartDB/" /etc/hosts
               failed $? "host entry exists, updating with DataMartDB"
        else
               failed 0 "host entry exists with dwdbmirror ip, nothing to do"
        fi
    fi
    if [ -z "$(grep "$sckBuildIp" /etc/hosts)" ] ; then
        echo "$sckBuildIp                     sckbuild.fastinc.com" >> /etc/hosts
        failed $? "writing sckbuild.fastinc.com to hosts file"
    else
        if [ -z "$(grep "sckbuild.fastinc.com" /etc/hosts)" ] ; then
               sed -i "s/\($sckBuildIp.*\)/\1  sckbuild.fastinc.com/" /etc/hosts
               failed $? "host entry exists, updating with  sckbuild.fastinc.com"
        else
               failed 0 "host entry exists with  sckbuild.fastinc.com ip, nothing to do"
        fi
    fi
    cd ~/
    failed $? "cd to root"
    echo "5am1am" > /root/rsync.passwd
    chmod 600 /root/rsync.passwd
    rsync -avhclz --progress --password-file=/root/rsync.passwd sckadmin@sckbuild.fastinc.com::staging/environment/wildflyinstall/$wildflyarch .
    failed $? "rsync $wildflyarch"
    unzip -o $wildflyarch
    failed $? "Unzip $wildflyarch"
    rm -f $wildflyarch
    failed $? "remove $wildflyarch"
    rm -rf /opt/$wildflyarchdir
    failed $? "removing old /opt/$wildflyarchdir"
    mv $wildflyarchdir/ /opt/
    failed $? "move wildfly directory to /opt"
    ln -s /opt/$wildflyarchdir /opt/wildfly
    failed $? "create symbolic link for /opt/wildfly/"
    if useradd -s/bin/bash -m wildfly
       	then
	echo "adding wildfly user"
    fi
    rsync -avhclz --progress --password-file=/root/rsync.passwd sckadmin@sckbuild.fastinc.com::staging/environment/wildfly/ .
    failed $? "rsync sybase driver for wildfly"
    cp -rf sybase $wildflydir/modules/system/layers/base/com/
    failed $? "move sybase driver to modules"
    cp -f standalone.xml $wildflydir/standalone/configuration
    failed $? "move standalone.xml to config dir"
    cp -f wildfly.conf $wildflydir/bin/init.d/wildfly.conf
    failed $? "move custom wildfly.conf to bin/init.d/wildfly.conf"
    cp $wildflydir/bin/init.d/wildfly.conf /etc/default/wildfly.conf
    failed $? "copy service config to /etc/default/wildfly/"
    cp $wildflydir/bin/init.d/wildfly-init-redhat.sh /etc/init.d/wildfly
    failed $? "copy service script to /etc/init.d/wildfly"
    chkconfig --add wildfly
    failed $? "adding wildfly service to init.d"
    chkconfig wildfly on
    failed $? "turning wildfly service on at startup"
    cp -f wildfly.lr /etc/logrotate.d/
    failed $? "move logrotate script to /etc/logrotate.d"
    mkdir -p /var/log/wildfly
    failed $? "mkdir /var/log/wildfly"
    chown -R wildfly:wildfly /var/log/wildfly
    failed $? "chown /var/log/wildfly"
    chown -R wildfly:wildfly $wildflydir
    failed $? "chown /opt/wildfly by wildfly"
    iptables -F
    failed $? "flush IP Table rules"
    iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    failed $? "Add IP Table rules"
    service iptables save
    failed $? "save IP Table rules"
    service iptables restart
    failed $? "Restart IP Tables"
    echo "Finished Installation of Wildfly at: $(date)"

    echo 5am1am > /root/rsyncd.passwd
    chmod 600 /root/rsyncd.passwd

    # Rsync the upgrade file
    rsync -avhclz --stats --progress --password-file /root/rsyncd.passwd ${builduid}@${buildserv}::latestqa/aboveStore/upgrade/qastaging/upgradeapiwildfly.sh ${downloadFiles}
    
    chmod +x ${downloadFiles}/upgradeapiwildfly.sh
    ${downloadFiles}/upgradeapiwildfly.sh

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
 
} >> $tmpLog

echo "Completed at $(date)" | mail -s "$HOSTNAME Updated successfully" $email
cat $tmpLog >> $log
cleanup 0
exit 0
