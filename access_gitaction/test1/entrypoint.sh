

#!/bin/bash


# 本地测试
# export gitcodeTargetBranch=master
export openGaussServer_Http_Repo_Url=https://gitcode.com/opengauss/openGauss-server.git

export WORKSPACE=/usr1/build/workspace

echo "-------------------------- start ci --------------------------"

echo "gitcodeTargetBranch: ${GITCODE_TARGET_BRANCH}"
echo "gitcodePullRequestIid: ${GITCODE_PR_IID}"
echo "gitcodeRef: ${gitcodeMergeRef}"
echo "parttype: ${PART_TYPE}"


echo "-------------------------- end ci --------------------------"