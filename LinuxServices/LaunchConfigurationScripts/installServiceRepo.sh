#!/bin/bash

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
tmpLog="/tmp/repoinstall.log"
log="/var/log/repoinstall.log"
accessKeyId="AKIAIRD4CSH2JFR2RD3A"
accessSecretAccessKey="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"
awsRegion="us-east-1"
loadBalancerName="repoelbexternal"
downloadFiles="/opt"
software="nexus"
softwareVersion="${software}-2.12.0-01"
downloadNexusZip="${softwareVersion}-bundle.zip"
jdkRpm="jdk-8u60-linux-x64.rpm"
sonaTypeWork="sonatype-work"
todayDate=$(date +%Y%m%d)

trap cleanup KILL TERM INT QUIT SIGKILL SIGINT
{
  # PreRequiste install JRE or JDK 
  cd ${downloadFiles}
  /usr/local/bin/aws s3 cp s3://kb-sck-softwares/jdk-1.8-installer-script/${jdkRpm} ${downloadFiles}
  rpm -ivh ${jdkRpm}
  failed $? "yum install java failed"
  rm -fr ${jdkRpm}

  # Install httpd
  yum -y install httpd
  failed $? "yum install httpd failed"

  chkconfig --level 234 httpd on

  # Install ssl
  yum -y install mod_ssl
  failed $? "yum install mod_ssl failed"

  # Download nexus and extract
  /usr/local/bin/aws s3 cp s3://kb-sck-softwares/Sonotype-Nexus/${downloadNexusZip} ${downloadFiles}
  unzip ${downloadNexusZip}
  failed $? "Download extract nexus failed"
  
  #Update hostname  
  perl -pi.orig -e 's/(HOSTNAME=).*/$1prd.repo2.mysck.internal/g;' /etc/sysconfig/network

  # Enable ports
  iptables -F
  iptables -A INPUT -p tcp --dport 8081 -j ACCEPT
  iptables -A INPUT -p tcp --dport 80 -j ACCEPT
  iptables -A INPUT -p tcp --dport 22 -j ACCEPT
  service iptables save
  service iptables restart

  # Add User nexus
  groupadd ${software}
  # nexus user changed permission
  useradd -g ${software} ${software}
  ln -s ${softwareVersion} ${software}
  chown -Rf ${software}.${software} /opt/${software}*

  # Copy file for startup
  cp ${downloadFiles}/${software}/bin/${software} /etc/init.d/

  # Update Nexus home
  perl -pi.orig -e 's/(NEXUS_HOME=").*/$1\/opt\/nexus"/gi;' /etc/init.d/${software} 
  
  perl -pi -e 's/#(RUN_AS_USER=)/$1nexus/gi;' /etc/init.d/${software}

  chmod 755 /etc/init.d/${software}
  chkconfig --add ${software}
  chkconfig --level 234 ${software} on

  # Sonatype work
  /usr/local/bin/aws s3 cp s3://kb-sck-softwares/Sonotype-Nexus/${sonaTypeWork}.zip /opt/
  unzip ${sonaTypeWork}.zip
  rm -fr ${sonaTypeWork}.zip
  chown -R nexus.nexus ${sonaTypeWork}  
 
  # Start nexus
  service nexus start
 
    # httpd configuration and start
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/Sonotype-Nexus/httpd.conf ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/Sonotype-Nexus/ssl.conf ${downloadFiles}
    
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/httpd-conf/ssl/ca-bundle.crt ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/httpd-conf/ssl/wildcard.key ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/httpd-conf/ssl/wildmysck.crt ${downloadFiles}
    
    mv /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf-orig
    mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf-orig
    
    mv httpd.conf /etc/httpd/conf/
    mv ssl.conf /etc/httpd/conf.d/
    
    mkdir /etc/httpd/conf/ssl
    mv ca-bundle.crt wildcard.key wildmysck.crt /etc/httpd/conf/ssl/

    # start httpd
    service httpd start

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

    #/usr/local/bin/aws ec2 create-snapshot --volume-id vol-1234567890abcdef0 --description "Repo Snapshot ${todayDate}"
  
} >> $tmpLog

echo "Completed at $(date)" | mail -s "${awsRegion} - $HOSTNAME - Nexus Repo installed successfully in Instance: ${instanceId}" $email
cat $tmpLog >> $log
cleanup 0
exit 0
 
