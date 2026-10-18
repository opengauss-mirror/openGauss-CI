#!/bin/bash
# pengass om 自动化升级测试脚本
# username:omm  usergroup:dbgrp 工具脚本路径：/usr1/opengaussautomattest/script xml文件路径：/usr1/clusterconfig.xml
#
# sh auto_upgradectl.sh /usr1/build/workspace ${gitcodeTargetBranch}
#

workdir=$1
branch=$2
echo -e "\033[32m 注意事项：  \033[0m"
echo -e "\033[32m       1、软件包路径请设置成不同于xml配置的安装路径以及日志保存路径 \033[0m"
echo -e "\033[32m       2、确保软件包路径除了xml配置不含有其他文件 \033[0m"
echo -e "\033[32m       3、需要互信的主机手动修改密码为设置密码  \033[0m"
echo -e "\033[32m       4、升级包命名为upgrade.tar.gz，并且解压以后文件夹名称为upgrade  \033[0m"

if [ $# -lt 2 ]; then
        echo -e "\033[31m 缺少参数，请检验参数长度 分别是 工作目录、软件包名称 \033[0m"
        exit
fi
scriptpath=${workdir}/om/package/script
BaseDb_scriptpath=${workdir}/openGauss/output/script
xmlpath=/data/om/cluster_1m0s_config.xml
BaseDb_xmlpath=/data/om/Base_cluster_1m0s_config.xml
username="autotest"
password=$(cat ${xmlpath} | grep -w "password" | awk -F'"' '{print $4}')
usergroup="dbgrp"
BaseDb_envfilepath="/home/${username}/Base_env"
envfilepath="/home/${username}/env"
logfilesavepath=/data/om/log


## 20240808开始更新包名，旧版本门禁都要兼容
upgradefilepath_om_old=${workdir}/openGauss/output/openGauss-$branch-openEuler-64bit-om.tar.gz
upgradefilepath_om_new=${workdir}/openGauss/output/openGauss-OM-$branch-openEuler20.03-x86_64.tar.gz
is_pkg_new=0
if [ -f "$upgradefilepath_om_old" ]; then
        upgradefilepath_om=$upgradefilepath_om_old
else
        upgradefilepath_om=$upgradefilepath_om_new
        is_pkg_new=1
fi
if [ "${is_pkg_new}" = "0" ]; then
        upgradefilepath_app=${workdir}/openGauss/output/openGauss-$branch-openEuler-64bit.tar.bz2
        upgradefilepath_app_sha256=${workdir}/openGauss/output/openGauss-$branch-openEuler-64bit.sha256
else
        upgradefilepath_app=${workdir}/openGauss/output/openGauss-Server-$branch-openEuler20.03-x86_64.tar.gz
        if [ ! -f "$upgradefilepath_app" ]; then
                upgradefilepath_app=${workdir}/openGauss/output/openGauss-Server-$branch-openEuler20.03-x86_64.tar.bz2
        fi
        upgradefilepath_app_sha256=${workdir}/openGauss/output/openGauss-Server-$branch-openEuler20.03-x86_64.sha256
fi
package_upgrade=${workdir}/openGauss/output/upgrade_sql.tar.gz
package_upgrade_sha256=${workdir}/openGauss/output/upgrade_sql.sha256


if [ "$gitcodeTargetBranch" == "2.0.0" ]; then
        base_package_path=/data/om/openGauss-2.0.0-openEuler-64bit-all.tar.gz
elif [[ "$gitcodeTargetBranch"x = "master"x || "$gitcodeTargetBranch"x = "7.0.0"x || "$gitcodeTargetBranch"x = "6.0.0"x || "$gitcodeTargetBranch"x = "6.0.5"x ]]; then
        base_package_path=/data/om/openGauss-All-6.0.0-openEuler20.03-x86_64.tar.gz
elif [ "$gitcodeTargetBranch" == "7.0.0-RC2" ]; then
        base_package_path=/data/om/openGauss-All-6.0.0-openEuler20.03-x86_64.tar.gz
elif [ "$gitcodeTargetBranch" == "7.0.0-RC1" ]; then
        base_package_path=/data/om/openGauss-All-6.0.0-openEuler20.03-x86_64.tar.gz
else
        base_package_path=/data/om/openGauss-3.0.0-openEuler-64bit-all.tar.gz
fi


hostname=$(hostname)
# sed -i "s/slave-x86-0007/${hostname}/g" ${xmlpath}
sed -i "s/HOSTNAMETOEDIT/${hostname}/g" ${xmlpath}
sed -i "s/HOSTNAMETOEDIT/${hostname}/g" ${BaseDb_xmlpath}

shellfilepath=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
# 用户校验
checkUser() {
        if [ $(env | grep USER | cut -d "=" -f 2) != "root" ]; then
                echo -e "\033[31m 当前登录的用户为 $(env | grep USER | cut -d "=" -f 2) 为避免未知异常，请使用root用户操作，其中涉及到om
                用户的操作，脚本会自动切换  \033[0m"
                echo -e "\033[31m 脚本退出 \033[0m"
                exit
        fi
}

main() {
        sync && echo 3 >/proc/sys/vm/drop_caches

        if [ -e ${workdir}/om/package/ ]; then
                rm -rf ${workdir}/om/package/*
        else
                mkdir -p ${workdir}/om/package
        fi
        tar -zxf ${base_package_path} -C ${workdir}/om/package/

        cd ${workdir}/om/package
        if [ "${is_pkg_new}" = "0" ]; then
                tar -xf `ls openGauss-*om*.tar.gz`
        else
                tar -xf `ls openGauss-OM-*.tar.gz`
        fi
        
        chmod -R 777 ${workdir}/om


        if [ ! -e ${scriptpath} ]; then
                echo -e "\033[31m 工具脚本路径不存在：${scriptpath} \033[0m"
        fi

        if [ ! -e ${BaseDb_xmlpath} ]; then
                echo -e "\033[31m 配置文件XML不存在：${xmlpath}  \033[0m"
        else
                BaseDb_installpath=$(cat ${BaseDb_xmlpath} | grep name=\"gaussdbAppPath\")
                BaseDb_installpath=${BaseDb_installpath#*/}
                BaseDb_installpath=${BaseDb_installpath%cluster*}
                echo "xml配置的安装路径：/$BaseDb_installpath"
                if [[ -n ${BaseDb_installpath} && -e /${BaseDb_installpath} ]]; then
                        rm -rf /${BaseDb_installpath}
                fi
        fi

        if [ ! -e ${xmlpath} ]; then
                echo -e "\033[31m 配置文件XML不存在：${xmlpath}  \033[0m"
        else
                installpath=$(cat ${xmlpath} | grep name=\"gaussdbAppPath\")
                installpath=${installpath#*/}
                installpath=${installpath%cluster*}
                echo "xml配置的安装路径：/$installpath"
                if [[ -n ${installpath} && -e /${installpath} ]]; then
                        rm -rf /${installpath}
                fi
        fi

        if [ ! -e ${envfilepath} ]; then
                touch ${envfilepath}
        else
                true >${envfilepath}
        fi
        #对环境变量文件赋权777
        chmod 777 ${envfilepath}

        chmod -R 777 ${workdir}
        echo -e "\033[32m 脚本存放路径：${scriptpath}；xml路径：${xmlpath}；用户名：${username}；用户组：${usergroup}；环境变量文件保存路径：${envfilepath}； \033[0m"
        #confirmContinue
        if [ -e ${logfilesavepath} ]; then
                rm -rf ${logfilesavepath}
                mkdir ${logfilesavepath}
                chmod -R 777 ${logfilesavepath}
                chown -R ${username}:${usergroup} ${logfilesavepath}
        else
                mkdir ${logfilesavepath}
                chmod -R 777 ${logfilesavepath}
                chown -R ${username}:${usergroup} ${logfilesavepath}
        fi

        #检查用户
        userexist=$(cat /etc/passwd | cut -f1 -d':' | grep -w "${username}" -c)
        if [ $userexist -gt 0 ]; then
                touch ${logfilesavepath}/cleanup.log
                chmod 777 ${logfilesavepath}/cleanup.log
                logdir=$(logCheck cleanup.log)
                userdel -r ${username} >${logdir} 2>&1
                processresult=$(cat ${logdir} | grep "is currently used by process")
                echo $processresult
                if [ -n "${processresult}" ]; then
                        #processresult=${processresult} | sed 's/ //g'
                        processresult1=${processresult#*process }
                        expr ${processresult1} + 1 >/dev/null
                        if [[ -n ${processresult1} && $? ]]; then
                                kill -9 ${processresult1}
                                userdel -r ${username}
                                echo "删除用户${username}"
                        fi
                fi
        fi
}

# 程序运行倒计时
countDown() {
        for i in $(seq 3 -1 1); do
                echo -en "\033[32m $1 操作将在 $i 秒后执行......\r \033[0m"
                sleep 1s
        done
}

# 脚本运行日志
logCheck() {
        if [ ! -e ${logfilesavepath}/$1 ]; then
                touch ${logfilesavepath}/$1
                chmod 777 ${logfilesavepath}/$1
        else
                true >${logfilesavepath}/$1
        fi
        echo "${logfilesavepath}/$1"
}

# 确认程序是否进行
confirmContinue() {
        echo "是否继续运行，确认（yes/no）"
        read confirmutils
        if [[ -n ${confirmutils} && ${confirmutils} != "yes" ]]; then
                echo "脚本退出"
                exit
        fi
}

# BaseDb预安装
BaseDb_preinstall() {
        logdir=$(logCheck gs_preinstall.log)
        if [ "${is_pkg_new}" = "0" ]; then
                tar -xf ${workdir}/openGauss/output/*om*.tar.gz -C ${workdir}/openGauss/output
                
        else
                tar -xf ${workdir}/openGauss/output/*OM*.tar.gz -C ${workdir}/openGauss/output
        fi
        cd /data/om
        

        ################### preinstall in docker has errors  #####################################
        ## [GAUSS-50802] : Failed to restart crond service. Error:
        ## System has not been booted with systemd as init system (PID 1). Can't operate.
        ## Failed to connect to bus: Host is down
        ###########################################################################################
        sed -i 's/self\.prepareSshdService/\#self.prepareSshdService/g' ${BaseDb_scriptpath}/impl/preinstall/PreinstallImpl.py
        sed -i 's/self\.prepareCronService/\#self.prepareCronService/g' ${BaseDb_scriptpath}/impl/preinstall/PreinstallImpl.py
        sed -i 's/self\.setAndCheckOSParameter/\#self.setAndCheckOSParameter/g' ${BaseDb_scriptpath}/impl/preinstall/PreinstallImpl.py

        echo "正在执行：${scriptpath}/gs_preinstall -U ${username} -G ${usergroup} -X ${BaseDb_xmlpath} --sep-env-file=${envfilepath}"
        #spawn ${scriptpath}/gs_preinstall -U ${username} -G ${usergroup} -X ${xmlpath} --sep-env-file=${envfilepath}
        expect -f $(dirname $0)/auto_preinstall.sh ${username} ${usergroup} ${BaseDb_xmlpath} ${BaseDb_envfilepath} ${BaseDb_scriptpath} ${password} | tee ${logdir}
        preinstallresult=$?
        preinstalllogcheck=$(cat ${logdir} | grep "Preinstallation succeeded")
        if [[ ${preinstallresult} == 0 && -n ${preinstalllogcheck} ]]; then
                echo -e "\033[32m 执行预安装操作成功 \033[0m"
                source ${BaseDb_envfilepath}
        else
                echo -e "\033[31m 执行预安装操作失败，日志同步保存在${logdir} \033[0m"
                echo -e "\033[31m 脚本即将退出 \033[0m"
                # cp /home/OM/ssh/* ~/.ssh/
                exit 1
        fi
}
# BaseDb安装
BaseDb_install() {
        chmod -R 755 ${scriptpath}
        chown -R ${username}:${usergroup} ${BaseDb_scriptpath}
        logdir=$(logCheck gs_install.log)
        echo " 正在执行：gs_install -X "
        #expect -c "set timeout 400;
        su - ${username} -c '
                source $1
                #$2/gs_install -X $3 | tee $4
                expect -f $2/auto_install.sh $3 $4 $5 | tee $6
        ' - ${BaseDb_envfilepath} ${shellfilepath} ${password} ${BaseDb_xmlpath} ${BaseDb_scriptpath} ${logdir}

        installresult=$?
        installlogcheck=$(cat ${logdir} | grep "Successfully installed application")
        if [[ ${installresult} == 0 && -n ${installlogcheck} ]]; then
                echo -e "\033[32m 执行安装操作成功 \033[0m"
        else
                echo -e "\033[31m 执行安装操作失败，日志同步保存在${logdir} \033[0m"
                # cp /home/OM/ssh/* ~/.ssh/
                exit 1
        fi
}
#BaseDb启动
BaseDb_startwithhostname() {
        logdir=$(logCheck starthostname.log)
        echo -e "\033[32m 正在执行start操作：gs_om -t start -h $(hostname) \033[0m"
        su - ${username} -c'
                source $1
                gs_om -t start -h $(hostname) | tee $2
        ' - ${BaseDb_envfilepath} ${logdir}
        starthresult=$?
        starthlogcheck=$(cat ${logdir} | grep "Successfully started")
        if [[ ${starthresult} == 0 && -n "${starthlogcheck}" ]]; then
                echo -e "\033[32m gs_om -t start -h $(hostname) 操作执行成功 \033[0m"
        else
                echo -e "\033[31m gs_om -t start -h $(hostname) 操作执行失败 \033[0m"
                # cp /home/OM/ssh/* ~/.ssh/
                exit 1
        fi
}

Install_Basedb() {
        datanode=/usr1/Base_opengaussautoinstall/cluster/data/dn1
        apppath=/usr1/Base_opengaussautoinstall/cluster/app
        mkdir -p ${apppath}
        mkdir -p ${datanode}
        tar -xf ${workdir}/openGauss/output/openGauss-Server*.tar.bz2 -C ${apppath}
        echo "export GAUSSHOME=/usr1/Base_opengaussautoinstall/cluster/app" >> ${BaseDb_envfilepath}
        echo "export LD_LIBRARY_PATH=/usr1/Base_opengaussautoinstall/cluster/app/lib:$LD_LIBRARY_PATH" >> ${BaseDb_envfilepath}
        echo "export PATH=/usr1/Base_opengaussautoinstall/cluster/app/bin:$PATH" >> ${BaseDb_envfilepath}

        chmod 755 ${BaseDb_envfilepath}
        chmod 755 -R /usr1/Base_opengaussautoinstall
        chown -R ${username}:${usergroup} /usr1/Base_opengaussautoinstall

        ## initdb & start db
        su - ${username} -c "source ${BaseDb_envfilepath}; gs_initdb -D ${datanode} --nodename=upgrade -w Test@123"
        su - ${username} -c "source ${BaseDb_envfilepath}; gs_guc set -D ${datanode} -c 'port=33000'"
        su - ${username} -c "source ${BaseDb_envfilepath}; gs_ctl start -D ${datanode}"

}
#数据采集
#只需要采集元数据，不使用om按照方式，直接initdb启动数据库采集，简化时间
gs_upgradechk() {
        echo "${branch}"
        if [[ "${gitcodeTargetBranch}"x = "master"x || "$gitcodeTargetBranch"x = "7.0.0"x ]]; then

                Install_Basedb

                echo "开始进行数据采集"
                output_pik=$(su ${username} -c '
                source $1
                output_pik=$(gs_upgradechk export -p 33000 )
                echo "$output_pik"
                code_path=$(echo "${output_pik}" | tail -n 1 | cut -d'\'':'\'' -f2 | tr -d '\''[:space:]'\'')
                echo "${code_path}"
' - ${envfilepath})
                export code_path=$(echo "$output_pik" | tail -n 1 | cut -d':' -f2 | tr -d "'[:space:]")
                echo "code_path: ${code_path}"
        fi
}

# UpgradeDb预安装
preinstall() {
        logdir=$(logCheck gs_preinstall.log)

        ################### preinstall in docker has errors  #####################################
        ## [GAUSS-50802] : Failed to restart crond service. Error:
        ## System has not been booted with systemd as init system (PID 1). Can't operate.
        ## Failed to connect to bus: Host is down
        ###########################################################################################
        sed -i 's/self\.prepareSshdService/\#self.prepareSshdService/g' ${scriptpath}/impl/preinstall/PreinstallImpl.py
        sed -i 's/self\.prepareCronService/\#self.prepareCronService/g' ${scriptpath}/impl/preinstall/PreinstallImpl.py
        sed -i 's/self\.setAndCheckOSParameter/\#self.setAndCheckOSParameter/g' ${scriptpath}/impl/preinstall/PreinstallImpl.py

        echo "正在执行：${scriptpath}/gs_preinstall -U ${username} -G ${usergroup} -X ${xmlpath} --sep-env-file=${envfilepath}"
        cd /data/om/
        #spawn ${scriptpath}/gs_preinstall -U ${username} -G ${usergroup} -X ${xmlpath} --sep-env-file=${envfilepath}
        expect -f $(dirname $0)/auto_preinstall.sh ${username} ${usergroup} ${xmlpath} ${envfilepath} ${scriptpath} ${password} | tee ${logdir}
        preinstallresult=$?
        preinstalllogcheck=$(cat ${logdir} | grep "Preinstallation succeeded")
        if [[ ${preinstallresult} == 0 && -n ${preinstalllogcheck} ]]; then
                echo -e "\033[32m 执行预安装操作成功 \033[0m"
                source ${envfilepath}
        else
                echo -e "\033[31m 执行预安装操作失败，日志同步保存在${logdir} \033[0m"
                echo -e "\033[31m 脚本即将退出 \033[0m"
                # cp /home/OM/ssh/* ~/.ssh/
                exit 1
        fi
}
# UpgradeDb安装
install() {
        chmod -R 755 ${scriptpath}
        chown -R ${username}:${usergroup} ${scriptpath}
        logdir=$(logCheck gs_install.log)
        echo " 正在执行：gs_install -X "
        #expect -c "set timeout 400;
        su - ${username} -c '
                source $1
                #$2/gs_install -X $3 | tee $4
                expect -f $2/auto_install.sh $3 $4 $5 | tee $6
        ' - ${envfilepath} ${shellfilepath} ${password} ${xmlpath} ${scriptpath} ${logdir}

        installresult=$?
        installlogcheck=$(cat ${logdir} | grep "Successfully installed application")
        if [[ ${installresult} == 0 && -n ${installlogcheck} ]]; then
                echo -e "\033[32m 执行安装操作成功 \033[0m"
        else
                echo -e "\033[31m 执行安装操作失败，日志同步保存在${logdir} \033[0m"
                # cp /home/OM/ssh/* ~/.ssh/
                exit 1
        fi
}
# UpgradeDb启动
startwithhostname() {
        logdir=$(logCheck starthostname.log)
        echo -e "\033[32m 正在执行start操作：gs_om -t start -h $(hostname) \033[0m"
        su - ${username} -c'
                source $1
                gs_om -t start -h $(hostname) | tee $2
        ' - ${envfilepath} ${logdir}
        starthresult=$?
        starthlogcheck=$(cat ${logdir} | grep "Successfully started")
        if [[ ${starthresult} == 0 && -n "${starthlogcheck}" ]]; then
                echo -e "\033[32m gs_om -t start -h $(hostname) 操作执行成功 \033[0m"
        else
                echo -e "\033[31m gs_om -t start -h $(hostname) 操作执行失败 \033[0m"
                # cp /home/OM/ssh/* ~/.ssh/
                exit 1
        fi
}

#升级
upgradectl() {
        chmod 777 ${upgradefilepath_om}
        chmod 777 ${upgradefilepath_app}
        chmod 777 ${upgradefilepath_app_sha256}

        if [[ $? == 0 ]]; then
                echo "准备进行升级包解压"
                if [ ! -e ${workdir}/package/upgrade/ ]; then
                        rm -rf ${workdir}/om/package/*
                        tar -zxf ${upgradefilepath_om} -C ${workdir}/om/package/
                        cp -rf ${upgradefilepath_app} ${workdir}/om/package/
                        cp -rf ${upgradefilepath_app_sha256} ${workdir}/om/package/
                        cp -rf ${package_upgrade} ${workdir}/om/package/
                        cp -rf ${package_upgrade_sha256} ${workdir}/om/package/
                fi
                if [ $? == 0 ]; then
                        echo "文件解压完成，准备执行预安装"
                        echo -e "\033[32m 准备执行预安装操作...... \033[0m"
                        echo -e "\033[32m 正在运行：${scriptpath}/gs_preinstall -U ${username} -G ${usergroup} -X ${xmlpath} --sep-env-file=${envfilepath};\033[0m"
                        logdir=$(logCheck gs_preinstall1.log)

                        ################### preinstall in docker has errors  #####################################
                        ## [GAUSS-50802] : Failed to restart crond service. Error:
                        ## System has not been booted with systemd as init system (PID 1). Can't operate.
                        ## Failed to connect to bus: Host is down
                        ###########################################################################################
                        sed -i 's/self\.prepareSshdService/\#self.prepareSshdService/g' ${scriptpath}/impl/preinstall/PreinstallImpl.py
                        sed -i 's/self\.prepareCronService/\#self.prepareCronService/g' ${scriptpath}/impl/preinstall/PreinstallImpl.py
                        sed -i 's/self\.setAndCheckOSParameter/\#self.setAndCheckOSParameter/g' ${scriptpath}/impl/preinstall/PreinstallImpl.py

                        ### 升级回滚
                        echo "######################################### 升级回滚检查 #####################################################"
                        expect -f $(dirname $0)/auto_preinstall.sh ${username} ${usergroup} ${xmlpath} ${envfilepath} ${scriptpath} ${password} | tee ${logdir}
                        preinstallresult=$?
                        preinstalllogcheck=$(cat $logdir | grep "Preinstallation succeeded")

                        if [[ ${preinstallresult} == 0 && -n ${preinstalllogcheck} ]]; then
                                echo -e "\033[32m 执行预安装操作成功，准备进行升级回滚操作 \033[0m"
                                logdir=$(logCheck upgradectl.log)
                                su - ${username} -c'
                                source $1
                                gs_upgradectl -t auto-upgrade -X $2 --grey | tee $3
                        ' - ${envfilepath} ${xmlpath} ${logdir}
                                upgraderesult=$?
                                upgradelogcheck=$(cat ${logdir} | grep "Upgrade main process has been finished")
                                if [[ ${upgraderesult} == 0 && -n ${upgradelogcheck} ]]; then
                                        echo -e "\033[32m 升级完成，进行gs_upgradectl -t auto-rollback回滚校验 \033[0m"
                                        logdir=$(logCheck upgradecheck.log)
                                        su - ${username} -c'
                                        source $1
                                        gs_upgradectl -t auto-rollback -X $2 | tee $3
                                ' - ${envfilepath} ${xmlpath} ${logdir}
                                        upgraderesult1=$?
                                        upgradelogcheck1=$(cat ${logdir} | grep "Successfully")
                                        if [[ ${upgraderesult1} == 0 && -n ${upgradelogcheck1} ]]; then
                                                echo -e "\033[32m 回滚完成 \033[0m"
                                                echo "############### 升级完成，打印回滚完后版本 #############"
                                                echo $(gaussdb -V)
                                                echo $(gs_om -V)
                                                echo "######################################################"
                                        else
                                                echo -e "\033[32m 升级完成，但是回滚检查不通过，建议手动检查是否正常回滚升级，确保功能无误 \033[0m"
                                        fi
                                else
                                        echo -e "\033[31m 升级失败 \033[0m"
                                        exit 1
                                fi
                        else
                                echo -e "\033[31m 执行预安装操作失败，升级终止 \033[0m"
                                exit 1
                        fi

                        ### 升级提交
                        echo "######################################### 升级提交检查 #####################################################"
                        expect -f $(dirname $0)/auto_preinstall.sh ${username} ${usergroup} ${xmlpath} ${envfilepath} ${scriptpath} ${password} | tee ${logdir}
                        preinstallresult=$?
                        preinstalllogcheck=$(cat $logdir | grep "Preinstallation succeeded")
                        if [[ ${preinstallresult} == 0 && -n ${preinstalllogcheck} ]]; then
                                echo -e "\033[32m 执行预安装操作成功，准备进行升级操作 \033[0m"
                                logdir=$(logCheck upgradectl.log)
                                su - ${username} -c'
                                source $1
                                gs_upgradectl -t auto-upgrade -X $2 --grey | tee $3
                        ' - ${envfilepath} ${xmlpath} ${logdir}
                                upgraderesult=$?
                                upgradelogcheck=$(cat ${logdir} | grep "Upgrade main process has been finished")
                                if [[ ${upgraderesult} == 0 && -n ${upgradelogcheck} ]]; then
                                        echo -e "\033[32m 升级完成，进行gs_upgradectl -t commit-upgrade校验 \033[0m"
                                        logdir=$(logCheck upgradecheck.log)
                                        su - ${username} -c'
                                        source $1
                                        gs_upgradectl -t commit-upgrade -X $2 | tee $3
                                ' - ${envfilepath} ${xmlpath} ${logdir}
                                        upgraderesult1=$?
                                        upgradelogcheck1=$(cat ${logdir} | grep "Successfully")
                                        if [[ ${upgraderesult1} == 0 && -n ${upgradelogcheck1} ]]; then
                                                echo -e "\033[32m 升级完成 \033[0m"
                                                echo "############### 升级完成，打印升级完后版本 #############"
                                                echo $(gaussdb -V)
                                                echo $(gs_om -V)
                                                echo "######################################################"
                                        else
                                                echo -e "\033[32m 升级完成，但是自动检查不通过，建议手动检查是否正常升级，确保功能无误 \033[0m"
                                        fi
                                else
                                        echo -e "\033[31m 升级失败 \033[0m"
                                        # cp /home/OM/ssh/* ~/.ssh/
                                        exit 1
                                fi
                        else
                                echo -e "\033[31m 执行预安装操作失败，升级终止 \033[0m"
                                exit 1
                                # cp /home/OM/ssh/* ~/.ssh/
                        fi
                else
                        echo "文件解压出错，升级终止"
                        # cp /home/OM/ssh/* ~/.ssh/
                        exit 1

                fi
        fi

}
#数据分析
gs_upgradechk_anl() {
        if [[ "${gitcodeTargetBranch}"x = "master"x || "$gitcodeTargetBranch"x = "7.0.0"x ]]; then
               code_path2=$( su ${username} -c '
                echo "开始进行数据分析"
                source /home/autotest/env
                output_anyl=$(gs_upgradechk verify -p 32000 -v ${code_path})
                echo "$output_anyl"
                code_path2=$(echo "${output_anyl}" | tail -n 1 | awk -F '\''：'\'' '\''{print $2}'\'' | tr -d '\''[:space:]'\'')
                echo "${code_path2}"
')
        
                echo "${code_path2}"
                cp /usr1/opengaussautoinstall/cluster/gaussdb_log/autotest/om/upgrade_checker/results/*.md /data/om/result/
                cp /usr1/opengaussautoinstall/cluster/gaussdb_log/autotest/om/upgrade_checker/results/*.md /data/om/result2/
                result=$(grep -l '成功' /data/om/result/V*.md)
                if [ -n "$result" ]; then
                        echo "元数据校验通过"
                else
                        echo "元数据校验失败"
                        exit 1
                fi
                rm -rf /data/om/result/*
        fi
}
# 卸载
uninstall() {
        logdir=$(logCheck gs_uninstall.log)
        echo -e "\033[32m 正在运行命令：gs_uninstall --delete-data \033[0m"
        su - ${username} -c'
                source $1
                gs_uninstall --delete-data | tee $2
        ' - ${envfilepath} ${logdir}
        uninstallresult=$?
        uninstalllogcheck=$(cat ${logdir} | grep "Uninstallation succeeded")
        if [[ ${uninstallresult} == 0 && -n "${uninstalllogcheck}" ]]; then
                echo -e "\033[32m 执行gs_uninstall --delete-data操作成功 \033[0m"
        else
                echo -e "\033[31m 执行gs_uninstall --delete-data操作失败 \033[0m"
                # cp /home/OM/ssh/* ~/.ssh/
                exit 1
        fi
}

# 清理环境变量
postuninstall() {
        echo -e "\033[32m 正在运行命令：${scriptpath}/gs_postuninstall -U ${username} -X ${xmlpath} --delete-user...... \033[0m"
        #source $envfilepath
        logdir=$(logCheck gs_postuninstall.log)
        # ${scriptpath}/gs_postuninstall -U ${username} -X ${xmlpath} --delete-user | tee $logdir
        expect -f $(dirname $0)/auto_postuninstall.sh ${username} ${usergroup} ${xmlpath} ${envfilepath} ${scriptpath} ${password} | tee ${logdir}
        clearresult=$?
        # 根据日志校验是否正常执行清理工作
        logcheck=$(cat ${logdir} | grep "Successfully cleaned environment")
        if [[ ${clearresult} == 0 && -n "${logcheck}" ]]; then
                echo -e "\033[32m 自动清理完成...... \033[0m"
        else
                echo -e "\033[31m 自动清理环境失败，请手动清理 command:gs_postuninstall -U ${username} -X ${xmlpath} --delete-user \033[0m"
                # cp /home/OM/ssh/* ~/.ssh/
                exit 1
        fi
}

main
# BaseDb_preinstall
# countDown "BaseDb安装"
# BaseDb_install
# countDown "BaseDb数据库启动 指定hostname"
# BaseDb_startwithhostname


countDown "UpgradeDb预安装"
preinstall
countDown "UpgradeDb安装"
install
countDown "UpgradeDb数据库启动 指定hostname"
startwithhostname
countDown "集群升级"
upgradectl

countDown "BaseDb开始安装，进行元数据校验-数据采集"
gs_upgradechk
countDown "开始进行元数据校验-数据分析"
gs_upgradechk_anl

countDown "数据库卸载"
uninstall
countDown "环境清理"
postuninstall
