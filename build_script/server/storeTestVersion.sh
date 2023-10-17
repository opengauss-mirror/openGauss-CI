#!/bin/bash

volume=$1
#区分release还是debug版本
pkg_type=$2
#区分5.1.0分支和master分支
build_type=$3
VERSION=5.1.0
test_version=$volume/archive_test
if [ X"${build_type}" == X"5.1.0" ]; then
    test_version=${test_version}/5.1.0
else
    test_version=${test_version}/master
fi

cd $volume
if [ -d $test_version ]; then
    rm -rf $test_version
fi
mkdir -p $test_version
pkg_list=("all.tar.gz" "Libpq.tar.gz" "symbol.tar.gz" "tools.tar.gz" "cm.tar.gz" "cm-symbol.tar.gz" "JDBC.tar.gz" "ODBC.tar.gz" "Python.tar.gz")
for suffix in ${pkg_list[@]}
do
    echo *$suffix
    cp *$suffix $test_version
done
cp openGauss-Lite* $test_version

cd $test_version
tar -zxf *all.tar.gz
rm -rf *all.tar.gz openGauss-Lite*Libpq.tar.gz openGauss-Lite*symbol.tar.gz openGauss-Lite*sha256
tar -zcf openGauss_${VERSION}_PACKAGES_RELEASE.tar.gz *

obs_upload_path=obs://opengauss-test/archive_test/${VERSION}

declare -A version_numbers
version_numbers["2023/04/12"]="openGauss5.1.0.B001"
version_numbers["2023/04/21"]="openGauss5.1.0.B002"
version_numbers["2023/04/26"]="openGauss5.1.0.B003"
version_numbers["2023/05/10"]="openGauss5.1.0.B004"
version_numbers["2023/05/17"]="openGauss5.1.0.B005"
version_numbers["2023/05/24"]="openGauss5.1.0.B006"
version_numbers["2023/05/31"]="openGauss5.1.0.B007"
version_numbers["2023/06/07"]="openGauss5.1.0.B008"
version_numbers["2023/06/14"]="openGauss5.1.0.B009"
version_numbers["2023/06/21"]="openGauss5.1.0.B010"
version_numbers["2023/06/28"]="openGauss5.1.0.B011"


function upload_package() {
    arch=$(uname -m)
    if [ "X$arch" == "Xaarch64" ]; then
        dbs_dest="arm"
	if [[ "x${volume}" =~ "x/data2" ]]; then
           dbs_dest=${dbs_dest}_2203
        fi
    else
        if [ -f "/etc/openEuler-release" ];then
            dbs_dest="x86_openEuler"
	    if [[ "x${volume}" =~ "x/data2" ]]; then
               dbs_dest=${dbs_dest}_2203
            fi
        else
            dbs_dest="x86"
        fi
    fi

    if [ "X$pkg_type" == "Xdebug" ]; then
	    dbs_test="${dbs_test}_debug"
    fi
    kernel=""
    version=""
    ext_version=""
    dist_version=""
    if [ -f "/etc/euleros-release" ]; then
        kernel=$(cat /etc/euleros-release | awk -F ' ' '{print $1}' | tr A-Z a-z)
        version=$(cat /etc/euleros-release | awk -F '(' '{print $2}'| awk -F ')' '{print $1}' | tr A-Z a-z)
        ext_version=$version
    elif [ -f "/etc/openEuler-release" ]; then
        kernel=$(cat /etc/openEuler-release | awk -F ' ' '{print $1}' | tr A-Z a-z)
        version=$(cat /etc/openEuler-release | awk -F '(' '{print $2}'| awk -F ')' '{print $1}' | tr A-Z a-z)
    elif [ -f "/etc/centos-release" ]; then
        kernel=$(cat /etc/centos-release | awk -F ' ' '{print $1}' | tr A-Z a-z)
        version=$(cat /etc/centos-release | awk -F '(' '{print $2}'| awk -F ')' '{print $1}' | tr A-Z a-z)
    else
        kernel=$(lsb_release -d | awk -F ' ' '{print $2}'| tr A-Z a-z)
        version=$(lsb_release -r | awk -F ' ' '{print $2}')
    fi

    if [ X"$kernel" == X"euleros" ]; then
        dist_version="EULER"
    elif [ X"$kernel" == X"centos" ]; then
        dist_version="CentOS"
    elif [ X"$kernel" == X"openeuler" ]; then
        dist_version="openEuler"
    else
        echo "Only support EulerOS|Centos|openEuler platform."
        echo "Kernel is $kernel"
        exit 1
    fi

    if [ X"${version_numbers[$(date '+%Y/%m/%d')]}" != X"" ]; then
        /home/obsutil cp openGauss_${VERSION}_PACKAGES_RELEASE.tar.gz ${obs_upload_path}/${version_numbers[$(date '+%Y/%m/%d')]}/${dbs_dest}/ -e obs.ap-southeast-1.myhuaweicloud.com 
    fi

}

upload_package
