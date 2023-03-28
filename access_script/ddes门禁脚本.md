# ddes门禁脚本

ddes主要有CBB，DSS，DMS三个门禁任务



CBB门禁脚本

```shell
CBB_GITEE_REPO=https://gitee.com/opengauss/CBB.git
third_party_binarylibs_package=xxxx
third_party_binarylibs_path=${WORKSPACE}/openGauss-third_party_binarylibs
# 1.下载CBB源码
git clone ${CBB_GITEE_REPO} -b ${branch}
# 2.下载三方库
wget -q -P ${WORKSPACE} ${third_party_binarylibs_package} -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz
# 3.编译CBB
cd ${WORKSPACE}/CBB/build/linux/opengauss
sh -x build.sh -3rd ${third_party_binarylibs_path} -m Release -t cmake
```



DSS门禁脚本

```shell
DSS_GITEE_REPO=https://gitee.com/opengauss/DSS.git
CBB_GITEE_REPO=https://gitee.com/opengauss/CBB.git
third_party_binarylibs_package=xxxx
third_party_binarylibs_path=${WORKSPACE}/openGauss-third_party_binarylibs
# 1.下载CBB，DSS源码
git clone ${CBB_GITEE_REPO} -b ${branch}
git clone ${DSS_GITEE_REPO} -b ${branch}
# 2.下载三方库
wget -q -P ${WORKSPACE} ${third_party_binarylibs_package} -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz
# 3.编译CBB
cd ${WORKSPACE}/CBB/build/linux/opengauss
sh -x build.sh -3rd ${third_party_binarylibs_path} -m Release -t cmake
# 4.编译DSS
cd ${WORKSPACE}/DSS/build/linux/opengauss
sh -x build.sh -3rd ${third_party_binarylibs_path} -m ReleaseDsstest -t cmake
```



DMS门禁脚本

```shell
CBB_GITEE_REPO=https://gitee.com/opengauss/CBB.git
DMS_GITEE_REPO=https://gitee.com/opengauss/DMS.git
third_party_binarylibs_package=xxxx
third_party_binarylibs_path=${WORKSPACE}/openGauss-third_party_binarylibs
# 1.下载CBB源码
git clone ${CBB_GITEE_REPO} -b ${branch}
git clone ${DMS_GITEE_REPO} -b ${branch}
# 2.下载三方库
wget -q -P ${WORKSPACE} ${third_party_binarylibs_package} -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz
# 3.编译CBB
cd ${WORKSPACE}/CBB/build/linux/opengauss
sh -x build.sh -3rd ${third_party_binarylibs_path} -m Release -t cmake
# 4.编译DMS
cd ${WORKSPACE}/DMS/build/linux/opengauss
sh -x build.sh -3rd ${third_party_binarylibs_path} -m Release -t cmake
```

