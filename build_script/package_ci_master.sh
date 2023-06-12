#!/bin/bash
set -e
arch="CentOS"

if [ ! -f /etc/centos-release ]; then
    arch="openEuler"
fi

DEPS_DIR=/usr1/build/workspace/dependency/
coretype=$(uname -p)
MAVEN_BIN="${DEPS_DIR}/apache-maven-3.6.3-bin.tar.gz"
JDK_BIN="${DEPS_DIR}/OpenJDK8U-jdk_x64_linux_hotspot_8u222b10.tar.gz"

if [ X"$coretype" == X"aarch64" ]; then
    JDK_BIN="${DEPS_DIR}/OpenJDK8U-jdk_aarch64_linux_hotspot_8u222b10.tar.gz"
fi


function log() {
    local level="$1"
    local msg_cont="$2"
    date_time=$(date +'%F %H:%M:%S')

    log_format="${date_time} [${level^^}] funcname: ${FUNCNAME[1]} line:$(caller 0 | awk '{print$1}') ${msg_cont}"
    case "${level}" in
        debug)
            echo -e "${log_format}"
            ;;
        info)
            echo -e "${log_format}"
            ;;
        warn)
            echo -e "${log_format}"
            ;;
        error)
            echo -e "${log_format}"
            ;;
    esac
}


function compile_init() {
    serverPkgPath=${workspace}/openGauss/server/build/script
    jdbcPkgPath=${workspace}/openGauss/jdbc
    odbcPkgPath=${workspace}/openGauss/odbc
    omPkgPath=${workspace}/openGauss/OM
    openGauss3rdbinarylibs=${workspace}/openGauss-third_party_binarylibs
    openGauss3rdbinarylibs_om=${workspace}/openGauss-third_party_binarylibs_om
    pythonDriver2Path=${workspace}/openGauss/python_driver2
    cmRestApiPath=${workspace}/openGauss/cm_restapi
	CMPkgPath=${workspace}/openGauss/CM
    cd ${pythonDriver2Path}
    rm -rf ${pythonDriver2Path}/output

    cd ${jdbcPkgPath}
    rm -rf *.jar
    rm -rf *.tar.gz
    rm -rf ${jdbcPkgPath}/output

    cd ${odbcPkgPath}
    rm -rf *.tar.gz
    rm -rf ${odbcPkgPath}/output

    cd ${serverPkgPath}
    log 'info' 'delete *tar.gz *zip *log reg.xml'
    rm -f *Gauss*.tar.gz
    rm -f *Gauss*.zip
    rm -f *PACKAGES*.tar.gz
    rm -f *PACKAGES*.tar.gz.sha256
    rm -f *PACKAGES*.zip
    rm -f *.log
    rm -f reg.xml
    rm -rf ${serverPkgPath}/../../output

    cd ${workspace}/openGauss/server/src ;rm -fr manager ;mkdir -p manager && ln -s ${workspace}/openGauss/OM manager/om
    cd ${workspace}/openGauss/server/build/script/
    chmod -R a+x *.sh
}

function touch_greyupgrade_flag() {
    cd ${workspace}/openGauss/server/output
    commit_id_openGauss=$(git rev-parse HEAD | cut -c 1-8)

    log 'debug' "gitnum=$commit_id_openGauss"
    echo $commit_id_openGauss > git_num.txt	
}


function get_gitnum() {
    cd ${workspace}/openGauss/server
    commit_id_openGauss=$(git rev-parse HEAD | cut -c 1-8)
    cd ${workspace}/openGauss/server/binarylibs
    commit_id_binarylibs=$(git rev-parse HEAD | cut -c 1-8)

    gitnum="${commit_id_openGauss}-${commit_id_binarylibs}"
    log 'debug' "gitnum=$gitnum"
    echo $gitnum > ${serverPkgPath}/svn_num.txt

}

function prepare_java_env()
{
    current_dir=$1
    THIRD_DIR=$current_dir/buildtools/
    mkdir -p $THIRD_DIR
    tar -zxvf $JDK_BIN -C $THIRD_DIR > /dev/null

    echo "Prepare the build enviroment."
    export JAVA_HOME=$THIRD_DIR/jdk8u222-b10
    export JRE_HOME=$JAVA_HOME/jre
    export LD_LIBRARY_PATH=$JRE_HOME/lib/amd64/server:$LD_LIBRARY_PATH
    export PATH=$JAVA_HOME/bin:$JRE_HOME/bin:$PATH	
    JAVA_VERSION=`java -version 2>&1 | awk -F '"' '/version/ {print $2}'`
    echo java version is $JAVA_VERSION
}

function prepare_maven_env()
{
    current_path=$1
    THIRD_DIR=$current_path/buildtools/maven
    mkdir -p $THIRD_DIR
    tar -zxvf $MAVEN_BIN -C $THIRD_DIR > /dev/null
    export MAVEN_HOME=$THIRD_DIR/apache-maven-3.6.3/
    export PATH=$MAVEN_HOME/bin:$PATH
    MAVEN_VERSION=`mvn -v 2>&1 | awk '/Apache Maven / {print $3}'`
    echo maven version is $MAVEN_VERSION
}

# compile DCF DCC CCB before CM
function compile_ddes_deps() {
    export PLAT_FORM_STR=$(sh ${omPkgPath}/build/get_PlatForm_str.sh)

    export GCC_PATH=${openGauss3rdbinarylibs}/buildtools/gcc7.3/
    export CC=$GCC_PATH/gcc/bin/gcc
    export CXX=$GCC_PATH/gcc/bin/g++
    export LD_LIBRARY_PATH=$GCC_PATH/gcc/lib64:$GCC_PATH/isl/lib:$GCC_PATH/mpc/lib/:$GCC_PATH/mpfr/lib/:$GCC_PATH/gmp/lib/:$LD_LIBRARY_PATH
    export PATH=$GCC_PATH/gcc/bin:$PATH

    if [ $1 = "debug" ]
    then
        pkg_type=Debug
    else
        pkg_type=Release
    fi

    cd ${workspace}/openGauss/CBB
    cd build/linux/opengauss
    sh -x build.sh -3rd ${openGauss3rdbinarylibs} -m ${pkg_type} -t cmake

    cd ${workspace}/openGauss/DCF
    export PLAT_FORM_STR=$(sh ${omPkgPath}/build/get_PlatForm_str.sh)
    cd build/linux/opengauss
    sh -x build.sh -3rd ${openGauss3rdbinarylibs} -m ${pkg_type} -t cmake

    cd ${workspace}/openGauss/DCC
    export PLAT_FORM_STR=$(sh ${omPkgPath}/build/get_PlatForm_str.sh)
    cd build/linux/opengauss
    sh -x build.sh -3rd ${openGauss3rdbinarylibs} -m ${pkg_type} -t cmake
}

function compile_ddes()
{
    if [ ! -d "${workspace}/openGauss/DSS" ]; then
        return 0
    fi
    export GCC_PATH=${openGauss3rdbinarylibs}/buildtools/gcc7.3/
    export CC=$GCC_PATH/gcc/bin/gcc
    export CXX=$GCC_PATH/gcc/bin/g++
    export LD_LIBRARY_PATH=$GCC_PATH/gcc/lib64:$GCC_PATH/isl/lib:$GCC_PATH/mpc/lib/:$GCC_PATH/mpfr/lib/:$GCC_PATH/gmp/lib/:$LD_LIBRARY_PATH
    export PATH=$GCC_PATH/gcc/bin:$PATH

    # 通过=分割字符，获取=后面的commit id
    list=($(awk -F= '{print $2}' ${workspace}/openGauss/server/src/gausskernel/ddes/ddes_commit_id))
    dms_commit_id=${list[0]}
    dss_commit_id=${list[1]}

    if [ $1 = "debug" ]
    then
        pkg_type=Debug
    else
        pkg_type=Release
    fi

    # DSS
    cd ${workspace}/openGauss/DSS
    git checkout ${dss_commit_id}
    cd ${workspace}/openGauss/DSS/build/linux/opengauss
    sh -x build.sh -3rd ${openGauss3rdbinarylibs} -m ${pkg_type}

    # DMS
    cd ${workspace}/openGauss/DMS
    git checkout ${dms_commit_id}
    cd ${workspace}/openGauss/DMS/build/linux/opengauss
    sh -x build.sh -3rd ${openGauss3rdbinarylibs} -m ${pkg_type}
}

function compile() {

    # CBB DCF DCC
    compile_ddes_deps
    compile_ddes

    # server
    cd ${serverPkgPath}
    local compile_type=$1
    local bepkit type=$2
    local compile_log=makepackage_${compile_type}.log
    local package_log=package_${compile_type}.log
    log 'debug' "compile log file is $compile_log,package log file is "
    cd ${serverPkgPath}/../../

    # 编译
    if [ -n "$bepkit_type" ]; then
        with_bepkit="-bepkit $bepkit_type"
    fi
    case $compile_type in
        debug)
            compile_command="sh build.sh -m debug -3rd ${openGauss3rdbinarylibs} -pkg"
            log "info" "exec: $compile_command"
            $compile_command | tee $compile_log
            ;;
        release)
            compile_command="sh build.sh -m release -3rd ${openGauss3rdbinarylibs} -pkg"
            log "info" "exec: $compile_command"
            $compile_command | tee $compile_log
            ;;
        memcheck)
            # low cpu version,without optimized,like arm
            compile_command="sh build.sh -m memcheck -3rd ${openGauss3rdbinarylibs} -pkg"
            log "info" "exec: $compile_command"
            $compile_command | tee $compile_log
            ;;
    esac
    # 判断是否编译成功
     if [ -f $compile_log ]; then
         # 值为1表示编译成功
         is_make_install_success=$(cat $compile_log makemppdb_pkg.log | grep "installation complete" | wc -l)
         if [ "$is_make_install_success" != 0 ]; then
             MakeStatus="success"
             MakeStatusnum=1
         elif [ "$is_make_install_success" = 0 ]; then
             MakeStatus="fail"
             MakeStatusnum=0
             log 'error' 'compile openGauss package failed'
             exit 1
         fi
     fi
    # 判断是否打包成功
    if [ -f $package_log ]; then
        # 值为1表示编译成功
        is_package_success=$(cat $package_log | grep "all packages has finished" | wc -l)
        if [ "$is_package_success" != 0 ]; then
            MakeStatus="success"
            MakeStatusnum=1
        elif [ "$is_package_success" = 0 ]; then
            MakeStatus="fail"
            MakeStatusnum=0
            log 'error' 'package openGauss failed'
            exit 1
        fi
    fi


    localIP=$(hostname -i | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
    localIP=${LocalIP//127\.0\.0\.1/}
    OSNAME=$(sed -n '/^ID=/{s/ID="//;s/"//p}' /etc/os-release)

    set +e
    # jdbc
    prepare_java_env ${jdbcPkgPath}
    prepare_maven_env ${jdbcPkgPath}
    cd ${jdbcPkgPath}
    sh build.sh
    cd ${jdbcPkgPath}/output
    if [ $(ls *.jar | wc -l) == 0 ]; then
       log 'err' 'build jdbc failed,skip it'
       exit 1
    fi
    tar -czvf openGauss-${VERSION}-JDBC.tar.gz postgresql.jar opengauss-jdbc-*.jar ../README_cn.md ../README_en.md

    # odbc
    cd ${odbcPkgPath}
    sh build.sh -bd ${serverPkgPath}/../../mppdb_temp_install
    cd ${odbcPkgPath}/output
    if [ $(ls *.tar.gz | wc -l) == 0 ]; then
        log 'err' 'build odbc failed, skip it'
        exit 1
    fi
    mv *.tar.gz openGauss-${VERSION}-ODBC.tar.gz

    # OM
    cd ${omPkgPath}
    sh build.sh -3rd ${openGauss3rdbinarylibs}
    cd ${omPkgPath}/package
    if [ $(ls *.tar.gz | wc -l) == 0 ]; then
        log 'err' 'build om failed'
        exit 1
    fi
    
    # psycopg2
    cd ${pythonDriver2Path}
    if [[ "$VERSION" =~ "3.0" ]]; then
        sh build.sh -bd ${serverPkgPath}/../../mppdb_temp_install
    else
        sh build.sh -bd ${serverPkgPath}/../../mppdb_temp_install -v ${VERSION}
    fi
    cd ${pythonDriver2Path}/output
    if [ $(ls *.tar.gz | wc -l) == 0 ]; then
        log 'err' 'build python driver2 failed, skip it'
        exit 1
    fi    

    # CM RestAPI
    if [ -d "$cmRestApiPath"]; then
        cd ${cmRestApiPath}
        sh build.sh
        if [ $(ls target/cmrestapi-*-RELEASE.jar | wc -l) == 0 ]; then
            log 'err' 'build cmRestApi failed, skip it'
            exit 1
        fi
    fi
    

    #CM
    cd ${CMPkgPath}
    sh build.sh -3rd ${openGauss3rdbinarylibs} -m ${compile_type} --pkg
    cd ${CMPkgPath}/output
    if [ $(ls *.tar.gz | wc -l) == 0 ]; then
        log 'err' 'build CM failed, skip it'
        exit 1
    fi
	mv *Package*.tar.gz openGauss-${VERSION}-$arch-64bit-cm.tar.gz
	mv *ymbols*.tar.gz openGauss-${VERSION}-$arch-64bit-cm-symbol.tar.gz

    if [ -f ${cmRestApiPath}/target/cmrestapi-*-RELEASE.jar ]; then
        mkdir cmtmp
        tar -zxf openGauss-${VERSION}-$arch-64bit-cm.tar.gz -C cmtmp
        cd cmtmp
        cp ${cmRestApiPath}/target/cmrestapi-*-RELEASE.jar ./bin/
        tar --owner=root --group=root -czf "openGauss-${VERSION}-$arch-64bit-cm.tar.gz" bin lib share tool
        mv openGauss-${VERSION}-$arch-64bit-cm.tar.gz ../
        cd ..
    fi

    sha256sum -b openGauss-${VERSION}-$arch-64bit-cm.tar.gz > openGauss-${VERSION}-$arch-64bit-cm.sha256

    set -e

}

function archive_package() {
    cd ${serverPkgPath}/../../output

    IsPkgExist=$(ls -l ./ | grep "openGauss" | wc -l)
    if [ $IsPkgExist -ne 0 ]; then
        CMP_TIPE=$(echo ${compile_type} | tr a-z A-Z)

        log 'info' 'archive package with tar'
        cp ${jdbcPkgPath}/output/*.tar.gz ./
        set +e
        cp ${odbcPkgPath}/output/*.tar.gz ./
        cp ${pythonDriver2Path}/output/*.tar.gz ./
        cp ${CMPkgPath}/output/*.tar.gz ./		
        set -e

        # om，server打包
		touch_greyupgrade_flag
        cp ${CMPkgPath}/output/*-cm.tar.gz ${omPkgPath}/package/.
        cp ${CMPkgPath}/output/*-cm.sha256 ${omPkgPath}/package/.
        cp openGauss-*.tar.bz2 ${omPkgPath}/package/.
        cp openGauss-*.sha256 ${omPkgPath}/package/.
        mv upgrade_sql.tar.gz ${omPkgPath}/package/.
        mv upgrade_sql.sha256 ${omPkgPath}/package/.
        cd ${omPkgPath}/package
        arch_name=$(ls | grep *.bz2 | awk -F '.tar.bz2' '{print $1}')
        tar zcfv ${arch_name}-all.tar.gz openGauss-*.tar.gz openGauss-*.tar.bz2 openGauss-*.sha256 upgrade_sql.tar.gz upgrade_sql.sha256
        cp ${arch_name}-all.tar.gz ${serverPkgPath}/../../output/.
        cd ${serverPkgPath}/../../output
        log 'info' 'packages name:'

        if [ -n ${OUTPUTFILE} ]; then
            cp *.tar.gz ${OUTPUTFILE}
			cp git_num.txt ${OUTPUTFILE}
            cp ${serverPkgPath}/*.log ${OUTPUTFILE}
            cp *.tar.bz2 ${OUTPUTFILE}
            cp *.sha256 ${OUTPUTFILE}
        fi
    else
        log 'error' 'not find openGauss package'
        exit 1

    fi

}

function compile_report() {
    echo -e "-----------编译结果-----------"
    echo -e "编译类型: $compile_type"
    echo -e "编译环境: $LocalIP"
    echo -e "编译结果: $MakeStatus"
    echo -e "编译告警: $warningnum"
    echo -e "编译错误: $errornum"
    echo -e "----------------------"
}


function usage() {
    echo ""
    echo "Usage: $0 <-d> [-b|-t|-b|-v|h]"
    echo "           -d <workspace>"
    echo "           -t <release| debug|memcheck>"
    echo "           -b <build|check>"
    echo "           -v <VERSION>"
    echo "           -h help"
    echo "EXAMPLE: $0 -d /usr1/gauss_jenkins/worspace -t release -v openGauss_500R001C00"


}

function main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    # 后续要与版本号分开
    VERSION="5.1.0"

    while getopts d:b:c:p:v:t:o:l:uh opt; do
        case "$opt" in
            d)
                workspace=$OPTARG
                ;;
            t)
                if [ $OPTARG == "release" -o $OPTARG == "debug" -o $OPTARG == "memcheck" -o $OPTARG == "release-L" ]; then
                    compile_type=$OPTARG
                else
                    usage
                    exit 1
                fi
                ;;
            b)
                if [ $OPTARG == "build" -o $OPTARG == "check" ]; then
                    bepkit_type=$OPTARG
                else
                    usage
                    exit 1
                fi
                ;;
            v)
                VERSION=$OPTARG
                ;;
            o)
                OUTPUTFILE=$OPTARG
                ;;
            l)
                THIRD_LIBS=$OPTARG
                ;;
            h | *)
                usage
                exit 1
                ;;
        esac
    done



    if [ -z $workspace ]; then
        log 'error' 'workspace not provided'
        usage
        exit 1
    fi
    if [ ! -d $workspace ]; then
        log 'error' "$workspace not find"
        exit 1
    fi

    if [ -n ${OUTPUTFILE} ]; then
        mkdir -p $OUTPUTFILE
        rm -rf $OUTPUTFILE/*PACKAGES*.tar.gz
        rm -rf $OUTPUTFILE/*PACKAGES*.tar.gz.sha256
        rm -rf $OUTPUTFILE/*PACKAGES*.zip
        # 单独归档删除的包
        rm -rf $OUTPUTFILE/*.tar.gz
        rm -rf $OUTPUTFILE/*.tar.gz.sha256
        rm -rf $OUTPUTFILE/*.xml
    fi

    if [ -n $compile_type ]; then
        compile_init
        compile $compile_type $bepkit_type
        archive_package
        compile_report
    fi
}
main $@


