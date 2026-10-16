#!/bin/bash
tools_path=/data/llt/PrivateBuild_tools
log_path=/data/llt/log
check_nu=$1
agent_path=$2
part=$3
# 测试用,正式需要注释掉
#gitcodeTargetBranch=3.0.0
#################################### create dir and logfile###########################################
test -d $log_path && rm -rf $log_path
mkdir $log_path
g_lltlog_dir=${tools_path}/log
g_lltlog_file=${g_lltlog_dir}/makemppdb_llt_$(printf "%.2d" ${check_nu})_$(date +'%Y%m%d_%H%M%S').log
mkdir -p ${g_lltlog_dir}
#################################### modify config.ini################################################
function modify_master() {
    sed -i "/update_for_wait_s1/d" "${agent_path}/src/test/regress/parallel_schedule0A"
    sed -i "/hw_partition_interval_dump_restore/d" "${agent_path}/src/test/regress/parallel_schedule0A"
    sed -i "/pl_debugger_server/d" "${agent_path}/src/test/regress/parallel_schedule0A"
    sed -i "/postgres_fdw_cstore/d" "${agent_path}/src/test/regress/parallel_schedule0A"
    sed -i "/vec_window_001/d" "${agent_path}/src/test/regress/parallel_schedule0B"
    sed -i "/ignore_type_transform/d" "${agent_path}/src/test/regress/parallel_schedule0C"
    sed -i "/row_compress_feature/d" "${agent_path}/src/test/regress/parallel_schedule0C"
    sed -i "/row_compression_basebackup/d" "${agent_path}/src/test/regress/parallel_schedule0C"
    sed -i "/component_view_enhancements/d" "${agent_path}/src/test/regress/parallel_schedule0C"
    sed -i "/db4ai_snapshots/d" "${agent_path}/src/test/regress/parallel_schedule0C"
    sed -i "/test_astore_multixact/d" "${agent_path}/src/test/regress/parallel_schedule0C"
    sed -i "/describe_index_with_tablespace/d" "${agent_path}/src/test/regress/parallel_schedule0C"
    sed -i "/nls_lower/d" "${agent_path}/src/test/regress/parallel_schedule0C"
    sed -i "/charset_d_format/d" "${agent_path}/src/test/regress/parallel_schedule0C"
    sed -i "/charset_b_format/d" "${agent_path}/src/test/regress/parallel_schedule0A"
}
#删除不稳定用例
function del_testcase() {
    sed -i "/rowlevelsecurity/d" "${agent_path}/src/test/regress/parallel_schedule"
    sed -i "/rowlevelsecurity/d" "${agent_path}/src/test/regress/parallel_schedule0"
    sed -i "/rowlevelsecurity/d" "${agent_path}/src/test/regress/parallel_schedule0B"
}
del_testcase
function modify_other() {
    sed -i "/ignore_type_transform/d" "${agent_path}/src/test/regress/parallel_schedule0"
    sed -i "/row_compress_feature/d" "${agent_path}/src/test/regress/parallel_schedule0"
    sed -i "/row_compression_basebackup/d" "${agent_path}/src/test/regress/parallel_schedule0"
    sed -i "/component_view_enhancements/d" "${agent_path}/src/test/regress/parallel_schedule0"
    sed -i "/db4ai_snapshots/d" "${agent_path}/src/test/regress/parallel_schedule0"
    sed -i "/update_for_wait_s1/d" "${agent_path}/src/test/regress/parallel_schedule0"
    sed -i "/hw_partition_interval_dump_restore/d" "${agent_path}/src/test/regress/parallel_schedule0"
    sed -i "/vec_window_001/d" "${agent_path}/src/test/regress/parallel_schedule0"
    sed -i "/test_astore_multixact/d" "${agent_path}/src/test/regress/parallel_schedule0"
    sed -i "/pl_debugger_server/d" "${agent_path}/src/test/regress/parallel_schedule0"
    sed -i "/describe_index_with_tablespace/d" "${agent_path}/src/test/regress/parallel_schedule0"
    sed -i "/postgres_fdw_cstore/d" "${agent_path}/src/test/regress/parallel_schedule0"
}

if [[ "$gitcodeTargetBranch"x = "2.0.0"x || "$gitcodeTargetBranch"x = "3.0.0"x || "$gitcodeTargetBranch"x = "dev"x ]]; then
    modify_other
else
    modify_master
fi

date
#################################### merge modify ##################################################
# echo merge_modify_start_time=$(date +%s.%N) >> ${g_lltlog_file} 2>&1
# sh  $tools_path/Private_Get_Modify.sh
# if [ $? -ne "0" ];then
    # printf "Failed to download the personal branch code! Error:\n"
    # [ -f "${log_path}/pullerror" ] && cat ${log_path}/pullerror
    # exit 1
# fi
# date
# echo merge_modify_stop_time=$(date +%s.%N) >> ${g_lltlog_file} 2>&1

#################################### check llt part ##################################################
if [ $check_nu -eq 4 ] ; then
    printf "Only check upgracheck in the LLT part 4\n"
    check_mode='fastcheck'
elif [ $check_nu -eq 99 ] ; then
    check_mode='fastcheck_single'
elif [ $check_nu -eq 0 ] ; then
    check_mode='fastcheck_single_opengauss'
    sed -i 's@MPPHOME=.*@MPPHOME=${g_boot_dir}/src/test/regress/tmp_check/install"${g_build_dir}"@g' $tools_path/config.ini
    sed -i 's@GAUSSHOME=.*$@GAUSSHOME=${g_boot_dir}/src/test/regress/tmp_check/install"${g_build_dir}"@g' $tools_path/config.ini
else
    check_mode='fastcheck_parallel_initdb'
fi

#################################### do llt job ##################################################
echo llt_job_start_time=$(date +%s.%N) >> ${g_lltlog_file} 2>&1

if [[ "$gitcodeTargetBranch"x = "2.0.0"x || "$gitcodeTargetBranch"x = "3.0.0"x || "$gitcodeTargetBranch"x = "dev"x ]]; then
    sh $tools_path/Private_LLT_Build.sh -m $check_mode -p $check_nu -c ${g_lltlog_file}
else
    sh $tools_path/Private_LLT_Build.sh -m $check_mode -p $check_nu -c ${g_lltlog_file} -t ${part}
fi
    
if [ $? -ne 0 ];then
    printf "Failed to make fastcheck! Please check the above logs to see the reason\n"
    exit 1
fi

echo llt_job_stop_time=$(date +%s.%N) >> ${g_lltlog_file} 2>&1
date

printf "====================================  Do LLT END  ========================================"

