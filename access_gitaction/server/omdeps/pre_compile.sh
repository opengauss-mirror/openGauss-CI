echo "gitcodePullRequestIid: ${gitcodePullRequestIid}"
echo "gitcodeAfterCommitSha: ${gitcodeAfterCommitSha}"
echo "gitcodeRef: ${gitcodeRef}"
git config --global core.compression 0

a=0
flag=0
while [ $a -lt 10 ]
do
   echo $a
   rm -rf ${WORKSPACE}/OM
   timeout 60 git clone -b ${gitcodeTargetBranch} "${openGaussOM_Http_Repo_Url}" "${WORKSPACE}/OM"
   if [[ $? == 0 ]] ; then
      flag=1
      break
   fi
   a=`expr $a + 1`
done

if [[ $flag == 0 ]] ; then
      echo "clone code failed!"
      exit 1
fi


cd ${WORKSPACE}/OM
git rev-parse --is-inside-work-tree
git config remote.origin.url ${openGaussOM_Http_Repo_Url}
git fetch --tags --force --progress origin ${gitcodeRef}:${gitcodeRef}
git checkout -b ${gitcodeRef} ${gitcodeRef}

echo "edit in background"

mkdir -p ${WORKSPACE}/openGauss/binarylibs
cd ${WORKSPACE}
rm -rf openGauss-third_party_binarylibs*
rm -rf om
set +x

#wget -q -P ${WORKSPACE} openGauss-third_party_binarylibs.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz
set -x
tar -zxf ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz


# 打包工程
cd /usr/bin
rm -rf python
ln -sf python2 python

cd ${WORKSPACE}/openGauss/build/script
chmod +x build_opengauss.sh
if [ $gitcodeTargetBranch = "2.0.0" ]; then
    sed -i 's/make -sj 8/make -sj20 /g' mpp_package.sh
fi
#sed -i 's/make install -sj 8/make install -sj 6 /g' mpp_package.sh

cd ${WORKSPACE}/openGauss
sh build.sh -m release -3rd ${WORKSPACE}/openGauss-third_party_binarylibs -pkg

# 打包om
cd ${WORKSPACE}/OM
sh build.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs

# copy om包
cp ${WORKSPACE}/OM/package/*om.tar.gz ${WORKSPACE}/openGauss/output/.


# 执行om
cd /usr/bin
rm -rf python
ln -sf python3 python
cd /data/om

pkg_branch="2.1.0"
if [ "${gitcodeTargetBranch}"x == "master"x ]; then
    pkg_branch="3.0.0"
elif [ "${gitcodeTargetBranch}"x == "3.0.0"x ]; then
    pkg_branch="3.0.0"
elif [ "${gitcodeTargetBranch}"x == "2.0.0"x ]; then
    pkg_branch="2.0.2"
else
    echo "expand as you need"
fi

echo "pakcage version is: $pkg_branch"
# 安装
sh automated-test.sh /usr1/build/workspace ${pkg_branch}

#升级(基础包未传入)
sh auto_upgradectl.sh /usr1/build/workspace ${pkg_branch}

if [ -e /home/OM/ssh/known_hosts ]
then
    rm -rf ~/.ssh/*
    cp /home/OM/ssh/* ~/.ssh/
fi
