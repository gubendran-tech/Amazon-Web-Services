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
downloadFiles="/opt/"
tmpLog="/tmp/mstrmwinstall.log"
log="/var/log/mstrmwinstall.log"
apacheTomcat="apache-tomcat-8.0.32"
loadBalancerName="mswselbexternal"
accessKeyId="AKIAIRD4CSH2JFR2RD3A"
accessSecretAccessKey="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"

# Below variables are the modification to staging and prod
awsRegion="us-east-1"
intelligenceServer="10.0.20.6 msis.production.mysck.internal"
indexHtml="prd-index.html"
adminServerXml="prd-AdminSevers.xml"

trap cleanup KILL TERM INT QUIT SIGKILL SIGINT
{
    # Install required libraries
    yum -y install libXp.x86_64 elfutils-devel.x86_64 elfutils-libelf-devel.x86_64 krb5-libs.i686 nss-pam-ldapd.i686 ksh-*.x86_64 compat-libstdc++-*.i686 nss-pam-ldapd.i686 libstdc++-*.i686 
    
    failed $? "yum install required libraries failed"

    # Install httpd
    yum -y install httpd
    failed $? "yum install httpd failed"

    chkconfig --level 234 httpd on
    
    # Update .bashrc
    echo "export AWS_ACCESS_KEY_ID=\"${accessKeyId}\""  >> ~/.bashrc
    echo "export AWS_SECRET_ACCESS_KEY=\"${accessSecretAccessKey}\""  >> ~/.bashrc
    echo "export AWS_DEFAULT_REGION=\"${awsRegion}\""  >> ~/.bashrc
    echo "export HISTSIZE=\"\"" >> ~/.bashrc
    echo "export CATALINA_HOME=\"/opt/${apacheTomcat}\"" >> ~/.bashrc
    echo "export JAVA_OPTS=\"-Xms512m -Xmx2048m\"" >> ~/.bashrc
    echo "export CATALINA_PID=\"\$CATALINA_HOME/bin/catalina.pid\"" >> ~/.bashrc
    source ~/.bashrc

    # Install Jdk
    cd ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/jdk-1.8-installer-script/jdk-8u60-linux-x64.rpm ${downloadFiles}
    rpm -ivh jdk-8u60-linux-x64.rpm
    failed $? "yum install java failed"
    rm -fr jdk-8u60-linux-x64.rpm
    
    # Install tomcat and user for tomcat
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/tomcat-8-installer-conf/${apacheTomcat}.tar.gz ${downloadFiles}
    tar -xzf ${apacheTomcat}.tar.gz
    rm -fr ${apacheTomcat}.tar.gz
    groupadd tomcat

    # tomcat user home directory changed
    useradd -g tomcat -d /opt/${apacheTomcat}/tomcat tomcat
    chown -Rf tomcat.tomcat /opt/${apacheTomcat}/ 
 
    # enable port for http and https
    iptables -F
    iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    service iptables save
    service iptables restart
    
    failed $? "iptables failed enabling"
    
    #tomcat configuration and start
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/tomcat-8-installer-conf/tomcat-users.xml ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/tomcat-8-installer-conf/server.xml ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/tomcat-8-installer-conf/tomcat ${downloadFiles}
    
    mv $CATALINA_HOME/conf/tomcat-users.xml $CATALINA_HOME/conf/tomcat-users.xml-orig
    mv $CATALINA_HOME/conf/server.xml $CATALINA_HOME/conf/server.xml-orig
    
    mv tomcat-users.xml server.xml $CATALINA_HOME/conf/
    mv tomcat /etc/init.d/
    chmod 755 /etc/init.d/tomcat
    chkconfig --add tomcat
    chkconfig --level 234 tomcat on
    
    # copy MSWM wars
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/MicroStrategyWebAndMobile-10.3-wars/MicroStrategy.war ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/MicroStrategyWebAndMobile-10.3-wars/MicroStrategyMobile.war ${downloadFiles}
    
    mv MicroStrategy.war $CATALINA_HOME/webapps/
    mv MicroStrategyMobile.war $CATALINA_HOME/webapps/
    
    # start tomcat
    /etc/init.d/tomcat start
    sleep 90s
   
    # copy web configuration file for Web and Mobile
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/MicroStrategyWebAndMobile-10.3-wars/${adminServerXml} ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/MicroStrategyWebAndMobile-10.3-wars/sys_defaults.properties ${downloadFiles}
    cp ${adminServerXml} /opt/${apacheTomcat}/webapps/MicroStrategy/WEB-INF/xml/${adminServerXml}  
    cp sys_defaults.properties /opt/${apacheTomcat}/webapps/MicroStrategy/WEB-INF/xml/sys_defaults.properties
    chown tomcat.tomcat /opt/${apacheTomcat}/webapps/MicroStrategy/WEB-INF/xml/${adminServerXml} 
    chown tomcat.tomcat /opt/${apacheTomcat}/webapps/MicroStrategy/WEB-INF/xml/sys_defaults.properties

    mv ${adminServerXml} /opt/${apacheTomcat}/webapps/MicroStrategyMobile/WEB-INF/xml/${adminServerXml}  
    mv sys_defaults.properties /opt/${apacheTomcat}/webapps/MicroStrategyMobile/WEB-INF/xml/sys_defaults.properties
    chown tomcat.tomcat /opt/${apacheTomcat}/webapps/MicroStrategyMobile/WEB-INF/xml/${adminServerXml} 
    chown tomcat.tomcat /opt/${apacheTomcat}/webapps/MicroStrategyMobile/WEB-INF/xml/sys_defaults.properties
 
    # This file has Map Key generated from Ryan user
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/MicroStrategyWebAndMobile-10.3-wars/esriConfig.xml ${downloadFiles}
    cp esriConfig.xml /opt/${apacheTomcat}/webapps/MicroStrategy/WEB-INF/xml/config/esriConfig.xml
    mv esriConfig.xml /opt/${apacheTomcat}/webapps/MicroStrategyMobile/WEB-INF/xml/config/esriConfig.xml

    chown tomcat.tomcat /opt/${apacheTomcat}/webapps/MicroStrategy/WEB-INF/xml/config/esriConfig.xml
    chown tomcat.tomcat /opt/${apacheTomcat}/webapps/MicroStrategyMobile/WEB-INF/xml/config/esriConfig.xml

    # httpd configuration and start
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/httpd-conf/httpd.conf ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/httpd-conf/proxy_ajp.conf ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/httpd-conf/ssl.conf ${downloadFiles}
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/httpd-conf/${indexHtml} ${downloadFiles}
    
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/httpd-conf/mod_ssl.so ${downloadFiles}
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
    mv ${indexHtml} /var/www/html/index.html
    
    mv mod_ssl.so /etc/httpd/modules/
    mkdir /etc/httpd/conf/ssl
    mv ca-bundle.crt wildcard.key wildmysck.crt /etc/httpd/conf/ssl/
    
    # httpd start
    /etc/init.d/httpd start
    
    # Copy cloudWatch modified perl script to support monitor pid
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/CloudWatch/mon-put-instance-data-modified.pl ${downloadFiles}
    mv /opt/aws-scripts-mon/mon-put-instance-data.pl /opt/aws-scripts-mon/mon-put-instance-data.pl-orig
    mv mon-put-instance-data-modified.pl /opt/aws-scripts-mon/mon-put-instance-data.pl
    chmod 755 /opt/aws-scripts-mon/mon-put-instance-data.pl
    
    # Copy cloudWatch for apache and tomcat too
    /usr/local/bin/aws s3 cp s3://kb-sck-softwares/CloudWatch/cloudWatchCron-httpd-tomcat ${downloadFiles}
    mv cloudWatchCron-httpd-tomcat /etc/cron.d/cloudWatch 
    
    instanceId=$(curl http://169.254.169.254/latest/meta-data/instance-id)
    /usr/local/bin/aws elb register-instances-with-load-balancer --load-balancer-name ${loadBalancerName} --instances ${instanceId}
    failed $? "adding elb"

    echo "${intelligenceServer}" >> /etc/hosts

} >> $tmpLog

echo "Completed at $(date)" | mail -s "$HOSTNAME - MSTR Web & Mobile installed successfully in Instance: ${instanceId}" $email
cat $tmpLog >> $log
cleanup 0
exit 0
