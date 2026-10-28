

#!/bin/bash


# 本地测试
# export gitcodeTargetBranch=master
export openGaussServer_Http_Repo_Url=https://gitcode.com/opengauss/openGauss-server.git

export WORKSPACE=/usr1/build/workspace

echo "-------------------------- start ci --------------------------"

echo "gitcodeTargetBranch: ${gitcodeTargetBranch}"
echo "gitcodePullRequestIid: ${gitcodePullRequestIid}"
echo "gitcodeAfterCommitSha: ${gitcodeAfterCommitSha}"
echo "gitcodeRef: ${gitcodeMergeRef}"
echo "parttype: ${PART_TYPE}"


echo "-------------------------- end ci --------------------------"