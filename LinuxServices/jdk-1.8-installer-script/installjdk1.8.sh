#!/bin/bash

cd ~
rsync -avh --progress sckadmin@sckbuild.fastinc.com::staging/environment/java8/jdk-8u60-linux-x64.rpm .
yum localinstall jdk-8u60-linux-x64.rpm
rm ~/jdk-8u60-linux-x64.rpm
