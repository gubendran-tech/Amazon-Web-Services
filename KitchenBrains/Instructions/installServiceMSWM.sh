#!/bin/bash

# Install required libraries
yum -y install libXp.x86_64 elfutils-devel.x86_64 elfutils-libelf-devel.x86_64 krb5-libs.i686 nss-pam-ldapd.i686 ksh-*.x86_64 compat-libstdc++-*.i686 nss-pam-ldapd.i686 libstdc++-*.i686 

# Install httpd
yum -y install httpd

# Install Jdk
cd /opt
curl https://s3-us-west-2.amazonaws.com/kb-sck-softwares/jdk-1.8-installer-script/jdk-8u60-linux-x64.rpm -O 
yum localinstall jdk-8u60-linux-x64.rpm
rm -fr jdk-8u60-linux-x64.rpm

# Install tomcat
curl https://s3-us-west-2.amazonaws.com/kb-sck-softwares/tomcat-8-installer-conf/apache-tomcat-8.0.32.tar.gz -O
tar -xzf apache-tomcat-8*.tar.gz

# Update .bashrc
echo "export HISTSIZE=""" >> ~/.bashrc
echo "export CATALINA_HOME=\"/opt/apache-tomcat-8.0.32\"" >> ~/.bashrc
echo "export JAVA_OPTS=$JAVA_OPTS -Xms512m -Xmx2048m" >> ~/.bashrc
source ~/.bashrc

# enable port for http and https
iptables -F
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
service iptables save
service iptables restart

#tomcat configuration and start
curl https://s3-us-west-2.amazonaws.com/kb-sck-softwares/tomcat-8-installer-conf/tomcat-users.xml -O
curl https://s3-us-west-2.amazonaws.com/kb-sck-softwares/tomcat-8-installer-conf/server.xml -O
curl https://s3-us-west-2.amazonaws.com/kb-sck-softwares/tomcat-8-installer-conf/index.html -O
curl https://s3-us-west-2.amazonaws.com/kb-sck-softwares/tomcat-8-installer-conf/tomcat -O

mv $CATALINA_HOME/conf/tomcat-users.xml $CATALINA_HOME/conf/tomcat-users.xml-orig
mv $CATALINA_HOME/conf/server.xml $CATALINA_HOME/conf/server.xml-orig
mv $CATALINA_HOME/webapps/ROOT/index.html $CATALINA_HOME/webapps/ROOT/index.html-orig

mv tomcat-users.xml server.xml $CATALINA_HOME/conf/
mv index.html $CATALINA_HOME/webapps/ROOT/
mv tomcat /etc/init.d/

# copy MSWM wars
curl https://s3-us-west-2.amazonaws.com/kb-sck-softwares/MicroStrategyWebAndMobile-10.3-wars/MicroStrategy.war -O
curl https://s3-us-west-2.amazonaws.com/kb-sck-softwares/MicroStrategyWebAndMobile-10.3-wars/MicroStrategyMobile.war -O

mv MicroStrategy.war $CATALINA_HOME/webapps/
mv MicroStrategyMobile.war $CATALINA_HOME/webapps/

# start tomcat
/etc/init.d/tomcat start

# httpd configuration and start
curl https://s3-us-west-2.amazonaws.com/kb-sck-softwares/httpd-conf/httpd.conf -O
curl https://s3-us-west-2.amazonaws.com/kb-sck-softwares/httpd-conf/proxy_ajp.conf -O
curl https://s3-us-west-2.amazonaws.com/kb-sck-softwares/httpd-conf/ssl.conf -O
curl https://s3-us-west-2.amazonaws.com/kb-sck-softwares/httpd-conf/index.html -O

mv /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf-orig
mv /etc/httpd/conf.d/proxy_ajp.conf /etc/httpd/conf.d/proxy_ajp.conf-orig
mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf-orig
mv /var/www/html/index.html /var/www/html/index.html-orig

mv httpd.conf /etc/httpd/conf/
mv proxy_ajp.conf /etc/httpd/conf.d/
mv ssl.conf /etc/httpd/conf.d/
mv index.html /var/www/html/

# httpd start
/etc/init.d/httpd start