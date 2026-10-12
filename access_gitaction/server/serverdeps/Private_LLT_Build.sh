#!/bin/bash
# 获取当前执行脚本绝对路径
path=$(dirname "${BASH_SOURCE-$0}")
real_path=$(
    cd "$path" >/dev/null
    pwd
)

# 定义函数，功能：引入配置文件 及 function目录下定义的函数
function source_file() {
    [ ! -f "${g_conf_file}" ] && echo "Can not find config file ${g_conf_file}" && exit 1

    # 去除配置文件中的\r字符
    config_str="$(cat "$g_conf_file" | grep -v "^[[:space:]]*$" |
        grep -v "^#" | tr -d '\r')"

    config_str_new="$config_str"
    #printf "$config_str_new\n"
    # 引入配置文件
    eval "$config_str"
    if [ $? -ne 0 ]; then
        echo "source ${g_conf_file} failed"
        return 1
    fi

    # source function目录下定义的函数
    while read line; do
        source "$line"
        if [ $? -ne 0 ]; then
            echo "source ${line} failed"
            return 1
        fi
    done <<_EOF_
$(find "${real_path}/function/" -mindepth 1 -maxdepth 1 \
        -name "[0-9][0-9].*.sh" -type f | sort)
_EOF_

    return 0
}

# 展示环境信息
function show_env_detail {
    # detect mppdb version information.
    VER_FILE=${g_boot_dir}/build/script/mppdb.ver

    if [ ! -f "${VER_FILE}" ]; then
        error "makemppdb" "Detect mppdb version information from ${VER_FILE} failed."
        error "makemppdb" "Details: can not find file ${VER_FILE} ."
        return 1
    fi

    eval $(cat ${VER_FILE})

    if [ "${V}" = "" -o "${R}" = "" -o "${C}" = "" ]; then
        error "makemppdb" "Detect mppdb version information from ${VER_FILE} failed."
        error "makemppdb" "Details: v version:${V}, r version:${R}, c version:${C}, a version:${OfficialVersion}, b version:${InternalVersion}"
        return 1
    else
        log "makemppdb" "Mppdb version "
    fi

    # get OS distributed version.
    os_name="$(get_osname)"
    if [ "${os_name}" = "" ]; then
        error "makemppdb" "Can not get OS type on Current node"
        return 1
    else
        log "makemppdb" "OS Type: ${os_name}"
    fi

    # show env var
    log "makemppdb" "Work  Dir: ${g_boot_dir}"
    log "makemppdb" "server  Dir: ${g_src_dir}"
    log "makemppdb" "Log   Dir: ${g_log_file}"
    log "makemppdb" "Build Dir: ${g_build_dir}"
    log "makemppdb" "Current       User: ${USER}"
    log "makemppdb" "Configure Pkg Type: ${g_release_mode}"
    log "makemppdb" "User for Fastcheck: ${g_execute_user}"
    log "makemppdb" "Port for Fastcheck: ${g_check_port}"

    log "makemppdb" "ENV VAR -- MPPHOME: ${MPPHOME}"
    log "makemppdb" "ENV VAR -- GAUSSHOME: ${GAUSSHOME}"
    log "makemppdb" "ENV VAR -- MPPDB_CODE: ${MPPDB_CODE}"
    log "makemppdb" "ENV VAR -- CC: ${CC}"
    log "makemppdb" "ENV VAR -- CXX: ${CXX}"
    log "makemppdb" "ENV VAR -- LD_LIBRARY_PATH: ${LD_LIBRARY_PATH}"
    log "makemppdb" "ENV VAR -- PATH: ${PATH}"

    log "makemppdb" "OPTION -- Retrans_enable: ${g_retrans_enable}"
    log "makemppdb" "OPTION -- g_master_user: ${g_master_user}"
    log "makemppdb" "OPTION -- g_master_log_path: ${g_master_log_path}"
    log "makemppdb" "OPTION -- g_top_build_id: ${g_top_build_id}"
    log "makemppdb" "OPTION -- g_cur_build_id: ${g_cur_build_id}"
}

function get_gcc_version() {
    os_name=$(
        source /etc/os-release
        echo $ID
    )
    cpu_arc=$(uname -p)
    if [[ "$cpu_arc"x = "x86_64"x ]]; then
        gcc_version="10.3.0"
    else
        gcc_version="10.3.1"
    fi
}

function compile_make() {
    #change current work dir to server
    log "makemppdb" "Change current dir to server dir"
    log "makemppdb" "Command: cd ${g_src_dir}"
    cd ${g_src_dir}
    if [ $? -ne 0 ]; then
        error "makemppdb" "Change dir failed"
        return 1
    fi

    #configure
    configure_start_time=$(date +%s.%N)
    log "makemppdb" "configure_start_time=${configure_start_time}"
    log "makemppdb" "Begin configure..."
    log "makemppdb" "Command: ./configure --gcc-version=${gcc_version} CC=g++ CFLAGS='-O0' --prefix=$g_build_dir --3rd=$binarylibs_path --enable-debug --enable-cassert --enable-thread-safety --with-readline --without-zlib"
    ./configure --gcc-version=${gcc_version} CC=g++ CFLAGS='-O0' --prefix=$g_build_dir --3rd=$binarylibs_path --enable-debug --enable-cassert --enable-thread-safety --with-readline --without-zlib

    if [ $? -ne 0 ]; then
        log "makemppdb" "configure failed, exit process."
        flag_configure_fail=1
        exit 1
    fi
    flag_configure_fail=0
    configure_end_time=$(date +%s.%N)
    log "makemppdb" "configure_end_time=${configure_end_time}"

    #make
    make_start_time=$(date +%s.%N)
    log "makemppdb" "make_start_time=${make_start_time}"
    echo "begin make opengauss..."
    make -sj16
    if [ $? -ne 0 ]; then
        flag_makeinstall_fail=1
        log "makemppdb" "make failed. exit process."
        exit 1
    fi
    make_end_time=$(date +%s.%N)
    log "makemppdb" "make_end_time=${make_end_time}"

    #make install
    makeinstall_start_time=$(date +%s.%N)
    log "makemppdb" "makeinstall_start_time=${makeinstall_start_time}"
    echo "begin make opengauss..."
    make install -sj16
    if [ $? -ne 0 ]; then
        flag_makeinstall_fail=1
        log "makemppdb" "make install failed. exit process."
        exit 1
    fi
    flag_makeinstall_fail=0
    makeinstall_end_time=$(date +%s.%N)
    log "makemppdb" "makeinstall_end_time=${makeinstall_end_time}"
}

function compile_cmake() {
    #change permission for work dir
    chmod 777 ${g_boot_dir}/../ 2>&1
    chown -R ${g_execute_user} ${g_boot_dir}/../* 2>&1

    #make
    make_start_time=$(date +%s.%N)
    log "makemppdb" "make_start_time=${make_start_time}"
    echo "begin make opengauss use cmake..."
    su - ${g_execute_user} -c " source /data/llt/PrivateBuild_tools/config_cmake.ini && mkdir -p ${g_src_dir}/tmp_build && cd ${g_src_dir}/tmp_build && cmake ${g_src_dir} -DENABLE_THREAD_SAFETY=ON -DWITH_READLINE=ON -DWITHZLIB=OFF -DENABLE_MULTIPLE_NODES=OFF -DENABLE_PRIVATEGAUSS=OFF -DENABLE_OPENSSL3=ON -DENABLE_MOT_SERVER=ON && make -sj16 && make install -sj16"
    if [ $? -ne 0 ]; then
	flag_configure_fail=1
        flag_makeinstall_fail=1
        log "makemppdb" "make failed. exit process."
        exit 1
    fi
    flag_configure_fail=0
    flag_makeinstall_fail=0
    make_end_time=$(date +%s.%N)
    log "makemppdb" "make_end_time=${make_end_time}"
}

function mk_fastcheck {
    if [[ "$gitcodeTargetBranch"x = "master"x || "$gitcodeTargetBranch"x = "7.0.0"x ]]; then
        compile_cmake
    else
        compile_make
    fi
    # make fastcheck
    chmod 777 ${g_boot_dir} 2>&1
    chown -R ${g_execute_user} ${g_boot_dir} 2>&1

    makefastcheck_start_time=$(date +%s.%N)
    log "makemppdb" "makefastcheck_start_time="${makefastcheck_start_time}""
    if [[ "$gitcodeTargetBranch"x = "master"x || "$gitcodeTargetBranch"x = "7.0.0"x ]]; then
        log "makemppdb" "Command: su - ${g_execute_user} -c \" source /data/llt/PrivateBuild_tools/config_cmake.ini && cd ${g_src_dir}/tmp_build/ && make fastcheck_single -sj p=${g_check_port} PART=${part} && make check -j16\""
        su - ${g_execute_user} -c " source /data/llt/PrivateBuild_tools/config_cmake.ini && cd ${g_src_dir}/tmp_build/ && make fastcheck_single -sj p=${g_check_port} PART=${part}"
		
		# 误触发布订阅
		# su - ${g_execute_user} -c " source /data/llt/PrivateBuild_tools/config_cmake.ini && cd ${g_src_dir}/tmp_build/ && make fastcheck_single -sj p=${g_check_port} PART=${part} && make check -j16"
    else
        log "makemppdb" "Command: su - ${g_execute_user} -c \"source $g_conf_file && export && cd \"${g_src_dir}/src/test/regress/\" && make fastcheck_single p=${g_check_port} -sj\""
        su - ${g_execute_user} -c " source $g_conf_file && export && cd ${g_src_dir}/src/test/regress/ && make fastcheck_single p=${g_check_port} -sj PART=${part} "
    fi

    if [ $? -ne 0 ]; then
        makefastcheck_stop_time=$(date +%s.%N)
        log "makemppdb" "makefastcheck_stop_time="${makefastcheck_stop_time}""
        error "makemppdb" "Make fastcheck failed."

        cat ${g_src_dir}/src/test/regress/log/initdb.log
        cat ${g_src_dir}/src/test/regress/log/postmaster_datanode1.log
        cat ${g_src_dir}/src/test/regress/regression.diffs
        cat ${g_src_dir}/src/test/regress/regression.out

	cat ${g_src_dir}/tmp_build/log/initdb.log
        cat ${g_src_dir}/tmp_build/log/postmaster_datanode1.log
        cat ${g_src_dir}/tmp_build/regression.diffs
        cat ${g_src_dir}/tmp_build/regression.out

        flag_makefastcheck_fail=1
        return 1
    else
        makefastcheck_stop_time=$(date +%s.%N)
        log "makemppdb" "makefastcheck_stop_time="${makefastcheck_stop_time}""
        flag_makefastcheck_fail=0
        log "makemppdb" "Make fastcheck succeed."
    fi
}

function transport_info {
    export g_aes_rand_key="$(date +%s%N)"
    g_trans_log_path=${g_master_log_path}/$(date +'%Y%m%d')_TID_${g_top_build_id}
    log "makemppdb" "Transport logs from agent($g_agent_ip:$g_log_file) to master($g_master_ip:$g_trans_log_path)..."
    if [ -z "$g_master_ip" -o \
        -z "$g_master_user" -o \
        -z "$g_master_password" -o \
        -z "$g_master_log_path" -o \
        -z "$g_top_build_id" -o \
        -z "$g_cur_build_id" \
        ]; then
        error "makemppdb" "Fail transport logs. Option Retrans parameters have error(s),please check"
        return 1
    fi
    res=0
    sh ${real_path}/function/remote.sh -i $g_master_ip -u $g_master_user -p "$g_master_password" -m "ssh-cmd" -t 100000 -c "mkdir -p $g_trans_log_path" 2>&1 >>${g_log_file}
    res=$(expr $res \| $?)
    for i in $(ls ${g_log_file%.log}*); do
        sh ${real_path}/function/remote.sh -i $g_master_ip -u $g_master_user -p "$g_master_password" -m "scp-out" -t 100000 -s $i -d $g_trans_log_path 2>&1 >>${g_log_file}
        res=$(expr $res \| $?)
        echo "DETAIL: ftp://mpp:mpp@$g_master_ip/log_fastcheck/${g_trans_log_path##*/}/${i##*/}" | tee -a ${g_log_file}
    done
    if [ $res -ne 0 ]; then
        error "makemppdb" "Fail transport logs"
    fi
}

function cal_interval_time {
    if [ $# -ne 2 ]; then
        printf "        "
        return 1
    fi
    local t=$(awk 'BEGIN{print '$2' - '$1'}')
    local z=${t%.*}
    printf "%.2d:%.2d:%.2d" $((z / 60 / 60)) $((z / 60 % 60)) $((z % 60))
}

function judge_time {
    local display="$1"
    local flag_fail=$2
    local start_time=$3
    local stop_time=$4
    if [ -z "$flag_fail" -o x"$flag_fail" = x"1" ]; then
        flag_str="Failure"
    else
        flag_str="Success"
    fi
    interval_time="$(cal_interval_time $start_time $stop_time)"
    [ -z "$start_time" ] && start_time="                   " || start_time=$(date -d @$start_time '+%Y-%m-%d %T')
    [ -z "$stop_time" ] && stop_time="                   " || stop_time=$(date -d @$stop_time '+%Y-%m-%d %T')
    printf "|$display| $flag_str     | $start_time | $stop_time |  $interval_time   |\n"
}
function gen_report {
    if [ "${check_mode}" = "fastcheck" -o "${check_mode}" = "fastcheck_parallel_initdb" -o "${check_mode}" = "fastcheck_single" -o "${check_mode}" = "fastcheck_single_opengauss" -o "${check_mode}" = "fastcheck_single_mot" ]; then
        printf "\
==============================================================================================
| Work Dir           | ${g_boot_dir}
| llt part           | ${check_part}
----------------------------------------------------------------------------------------------
| Stage              | Status      | Start Time          | Stop Time           |  Exec Time  |
|--------------------------------------------------------------------------------------------|
"
        judge_time " configure          " "${flag_configure_fail}" "$configure_start_time" "$configure_stop_time"

        judge_time " make install       " "${flag_makeinstall_fail}" "$makeinstall_start_time" "$makeinstall_stop_time"
        judge_time " make ${check_mode} " "${flag_makefastcheck_fail}" "$makefastcheck_start_time" "$makefastcheck_stop_time"
        interval_total_time="$(cal_interval_time $total_start_time $total_stop_time)"
        echo ----------------------------------------------------------------------------------------------
        echo "FASTCHECK TOTAL TIME: $interval_total_time"
        echo
    fi
}
function clean_env {
    for u in $(echo $g_clean_user | sed 's/,/ /g'); do
        cleanEnv_ipcs $u
    done

    ps -ef | grep ${g_src_dir}/src/distribute/test/regress | grep -v grep | awk '{print $2}' | xargs kill -9 >/dev/null 2>&1 || sleep 0
    ps -ef | grep ${g_src_dir}/src/test/regress | grep -v grep | awk '{print $2}' | xargs kill -9 >/dev/null 2>&1 || sleep 0

    rm -rf ${g_src_dir}/src/backend/catalog/postgres.bki
    rm -rf ${g_src_dir}/src/distribute/test/regress/tmp_check
    rm -rf ${g_src_dir}/src/distribute/test/regress/log

    sudo sh -c "echo 1 > /proc/sys/vm/drop_caches"
    sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"
    umask 022
}

# main function
function main {
    total_start_time=$(date +%s.%N)

    echo ========================================================================================== | tee -a ${g_log_file}
    show_env_detail
    echo | tee -a ${g_log_file}

    echo ========================================================================================== | tee -a ${g_log_file}
    clean_env 2>&1 | tee -a ${g_log_file}
    echo | tee -a ${g_log_file}

    echo ========================================================================================== | tee -a ${g_log_file}
    if [ "${check_mode}" = "commitcheck" ]; then
        check_ci
    elif [ "${check_mode}" = "fastcheck" -o "${check_mode}" = "fastcheck_parallel_initdb" -o "${check_mode}" = "fastcheck_single" -o "${check_mode}" = "fastcheck_single_opengauss" -o "${check_mode}" = "fastcheck_single_mot" ]; then
        mk_fastcheck
        if [ $? -ne 0 ]; then
            error "makemppdb" "Fail make fastcheck"
        fi
    fi
    echo | tee -a ${g_log_file}

    total_stop_time=$(date +%s.%N)

    gen_report 2>&1 | tee -a ${g_log_file}

    # if [ $g_retrans_enable -eq 1 ]; then
    # transport_info
    # fi

    if [ "${flag_makeinstall_fail}" == 1 ] || [ "${flag_makefastcheck_fail}" == 1 ] || [ "${flag_makeclean_fail}" == 1 ]; then
        error "makemppdb" "Exit the make fastcheck whith error."
        exit 1
    fi
}

# 帮助
function show_help {
    echo
    echo "Usage: $(basename $0) [option]"
    echo "options:"
    echo "-m                    Notes: check mode"
    echo "-p                    Notes: check part"
    echo "-c                    Notes: hdfs_conf_path"
    echo "-d                    Notes: top mission build id"
    echo "-t                    Notes: specify the file for fastcheck"
    echo "-h                    Notes: help"
    echo
    echo "Example:"
    echo "$(basename $0)"
    echo
    return 0
}

# 获取入参
while getopts "m:p:c:d:t:h" options; do
    case ${options} in
    m)
        check_mode="${OPTARG}"
        ;;
    p)
        check_part="${OPTARG}"
        ;;
    c)
        log_file="${OPTARG}"
        ;;
    d)
        top_build_id="${OPTARG}"
        ;;
    t)
        part="${OPTARG}"
        ;;
    h)
        show_help
        exit 1
        ;;
    *)
        show_help
        exit 1
        ;;
    esac
done

if [ -z "$check_mode" ]; then
    echo "ERROR: need -m"
    show_help
    exit 1
fi

# 测试需要,上线门禁需要删除
#gitcodeTargetBranch=master

function export_config_file() {
    # 引入配置文件 及 function目录下定义的函数
    g_conf_file=/data/config/config_gcc10.ini
    cpu_arc=$(uname -p)
    if [[ "$gitcodeTargetBranch"x = "2.0.0"x ]]; then
        g_conf_file=/data/config/config_old.ini
    elif [[ "$gitcodeTargetBranch"x = "3.0.0"x || "$gitcodeTargetBranch"x = "5.0.0"x ]]; then
        g_conf_file=/data/config/config_gcc7.ini
    elif [[ "$gitcodeTargetBranch"x = "master"x || "$gitcodeTargetBranch"x = "5.1.0"x || "$gitcodeTargetBranch"x = "dev"x ]]; then
        g_conf_file=/data/config/config_gcc10.ini
    fi

    source_file
}

function export_gcc_version() {
    gcc_version="10.3.1"
    os_name=$(
        source /etc/os-release
        echo $ID
    )
    if [[ "$gitcodeTargetBranch"x = "2.0.0"x || "$gitcodeTargetBranch"x = "3.0.0"x || "$gitcodeTargetBranch"x = "5.0.0"x ]]; then
        gcc_version="7.3.0"
    elif [[ "$gitcodeTargetBranch"x = "5.1.0"x || "$gitcodeTargetBranch"x = "6.0.0"x || "$gitcodeTargetBranch"x = "master"x || "$gitcodeTargetBranch"x = "dev"x || "$gitcodeTargetBranch"x = "dev_board"x ]]; then
        if [[ "$os_name"x = "centos"x ]]; then
            gcc_version="10.3.0"
        elif [[ "$os_name"x = "openEuler"x ]]; then
            gcc_version="10.3.1"
        fi
    fi
    echo "$gcc_version"
}

export_config_file
export_gcc_version

# 定义日志目录
#g_log_dir=${real_path}/log
[ -z "${g_cur_build_id}" ] && g_cur_build_id=xx
[ -z "${g_top_build_id}" ] && g_top_build_id=xx
#g_log_file=${g_log_dir}/makemppdb_ID_${g_cur_build_id}_$(date +'%Y%m%d_%H%M%S').log
#g_log_file=${g_log_dir}/makemppdb_llt_$(printf "%.2d" ${check_part})_$(date +'%Y%m%d_%H%M%S').log
g_log_file=${log_file}

# 当前ip
g_agent_ip=$(echo "${SSH_CONNECTION}" | awk '{print $3}')

# 主程序入口
main


