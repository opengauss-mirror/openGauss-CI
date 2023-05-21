#!/bin/bash
set -x
echo "giteePullRequestIid: ${giteePullRequestIid}"
echo "giteeAfterCommitSha: ${giteeAfterCommitSha}"
echo "giteeRef: ${giteeRef}"
git config --global core.compression 0

sync && echo 3 >/proc/sys/vm/drop_caches
ipcrm -a

dbMind_repo=https://gitee.com/opengauss/openGauss-DBMind.git

function down_soure_from_gitee() {
    repo=$1
    branch=$2
    target_dir=$3

    a=0
    flag=0
    while [ $a -lt 3 ]; do
        echo $a
        rm -rf ${WORKSPACE}/${target_dir}
        timeout 60 git clone ${repo} -b ${branch} "${WORKSPACE}/${target_dir}"
        if [[ $? == 0 ]]; then
            flag=1
            break
        fi
        a=$(expr $a + 1)
    done

    if [[ $flag = 0 ]]; then
        echo "clone ${target_dir} failed!"
        exit 1
    fi
}

function down_source() {
    down_soure_from_gitee ${dbMind_repo} ${giteeTargetBranch} dbmind
}

function merge_source_code() {
    cd ${WORKSPACE}/dbmind || exit
    git rev-parse --is-inside-work-tree
    git config remote.origin.url ${dbMind_repo}
    git fetch --tags --force --progress origin ${giteeRef}:${giteeRef}
    git checkout -b ${giteeRef} ${giteeRef}
}

function package() {
    cd ${WORKSPACE}/dbmind || exit
    sh package.sh
    if [[ $? == 0 ]]; then
        echo "dbmind package success."
    else
        echo "dbmind package failed."
        exit 1
    fi
}

function main() {
    down_source
    merge_source_code
    package
}

main "$@"
