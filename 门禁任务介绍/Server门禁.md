
### openGauss-server仓库门禁说明

openGauss-server仓库总共运行6类任务：

| 任务名称 | 任务描述 |
|:---| :--- |
| openGauss_server_PrivateBuild_LLT_Single-mot | MOT用例-开发者测试 |
| openGauss_server_PrivateBuild_LLT_arm_00 |  功能用例-开发者测试-ARM平台 |
| openGauss_server_PrivateBuild_LLT_x86_00 |  功能用例-开发者测试-x86平台 |
| openGauss_server_PrivateBuild_Compile_x86 | 代码编译测试 |
| openGauss_server_PrivateBuild_LLT_SS | 共享存储测试用例  |
| openGauss_server_OM_install_upgrade  | OM+Server安装升级测试 |


### MOT用例 (openGauss_server_PrivateBuild_LLT_Single-mot)

该门禁运行基础的MOT，即内存表功能测试用例

1. 导入环境变量
   
```
export CODE_BASE=${WORKSPACE}/openGauss-server   # openGauss-server源码路径
export BINARYLIBS=${WORKSPACE}/openGauss-third_party_binarylibs_openEuler_x86_64   # 依赖的三方库二进制文件解压路径
export GAUSSHOME=$CODE_BASE/dest/
export GCC_PATH=$BINARYLIBS/buildtools/gcc7.3/
export CC=$GCC_PATH/gcc/bin/gcc
export CXX=$GCC_PATH/gcc/bin/g++
export LD_LIBRARY_PATH=$GAUSSHOME/lib:$GCC_PATH/gcc/lib64:$GCC_PATH/isl/lib:$GCC_PATH/mpc/lib/:$GCC_PATH/mpfr/lib/:$GCC_PATH/gmp/lib/:$LD_LIBRARY_PATH
export PATH=$GAUSSHOME/bin:$GCC_PATH/gcc/bin:$PATH
```

2. 编译
```
./configure --gcc-version=7.3.0 CC=g++ CFLAGS='-O0' --prefix=$GAUSSHOME --3rd=$BINARYLIBS --enable-debug --enable-cassert --enable-thread-safety --with-readline --without-zlib --enable-mot

make -sj
make install -sj
```
3. 运行用例
```
make fastcheck_single_mot
```

### 功能用例-开发者测试

> openGauss_server_PrivateBuild_LLT_x86_00
> openGauss_server_PrivateBuild_LLT_arm_00

该用例在Centos7.6-x86_64和 openEuler20.03LTS-ARM两个平台上执行开发者测试命令。所使用命令一致。

1. 导入环境变量
   
```
export CODE_BASE=${WORKSPACE}/openGauss-server   # openGauss-server源码路径
export BINARYLIBS=${WORKSPACE}/openGauss-third_party_binarylibs_openEuler_x86_64   # 依赖的三方库二进制文件解压路径
export GAUSSHOME=$CODE_BASE/dest/
export GCC_PATH=$BINARYLIBS/buildtools/gcc7.3/
export CC=$GCC_PATH/gcc/bin/gcc
export CXX=$GCC_PATH/gcc/bin/g++
export LD_LIBRARY_PATH=$GAUSSHOME/lib:$GCC_PATH/gcc/lib64:$GCC_PATH/isl/lib:$GCC_PATH/mpc/lib/:$GCC_PATH/mpfr/lib/:$GCC_PATH/gmp/lib/:$LD_LIBRARY_PATH
export PATH=$GAUSSHOME/bin:$GCC_PATH/gcc/bin:$PATH
```

2. 编译
```
./configure --gcc-version=7.3.0 CC=g++ CFLAGS='-O0' --prefix=$GAUSSHOME --3rd=$BINARYLIBS --enable-debug --enable-cassert --enable-thread-safety --with-readline --without-zlib

make -sj
make install -sj
```
3. 运行用例
```
make fastcheck_single
```

### 代码编译测试

针对提交代码，进行编译测试，检查是否能够编译通过。包含makefile和cmake两种测试。

1. makefile编译
```
cd ${WORKSPACE}/openGauss-server                                              # openGauss-server源码路径
sh build.sh ${WORKSPACE}/openGauss-third_party_binarylibs_openEuler_x86_64    # 依赖的三方库二进制文件解压路径
```

2. cmake编译
```
## 将build_opengauss.sh中的CMAKE_PKG改为Y，则一键式脚本使用的cmake编译。
cd ${WORKSPACE}/openGauss-server/build/script
sed -i "s/CMAKE_PKG=\"N\"/CMAKE_PKG=\"Y\"/" build_opengauss.sh

cd ${WORKSPACE}/openGauss-server                                              # openGauss-server源码路径
sh build.sh ${WORKSPACE}/openGauss-third_party_binarylibs_openEuler_x86_64    # 依赖的三方库二进制文件解压路径
```

### 共享存储测试用例

共享存储测试，使用dd模拟出来写块设备，使用dss初始化块设备以及启动dssserver，然后openGauss基于块设备作为存储进行初始化数据库以及启动。

需要下载CBB、DSS、DMS、openGauss-server仓库代码。由于DSS和DMS有版本控制，还需要将DSS和DMS按照openGauss-server里面回退到指定版本。

1. 下载CBB、DSS、DMS、openGauss-server相同分支代码。
2. 查看openGauss-server中`src/gausskernel/ddes/ddes_commit_id`，里面分别有dss和dms要求的commitid，将dss和dms代码回退到该对应commit点。
```
list=($(awk -F= '{print $2}' ${WORKSPACE}/openGauss-server/src/gausskernel/ddes/ddes_commit_id))
dms_commit_id=${list[0]}
dss_commit_id=${list[1]}

cd ${WORKSPACE}/DSS
git checkout ${dss_commit_id}

cd ${WORKSPACE}/DMS
git checkout ${dms_commit_id}
```

3. 编译依赖CBB|DMS|DSS
```
## CBB
cd ${WORKSPACE}/CBB/build/linux/opengauss
sh -x build.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs

## DSS
cd ${WORKSPACE}/DSS/build/linux/opengauss
sh -x build.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs -m ReleaseDsstest -t cmake

## DMS
cd ${WORKSPACE}/DMS/build/linux/opengauss
sh -x build.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs
```

4. 编译数据库
数据库通过CMKAE方式编译
```
cd ${WORKSPACE}/openGauss-server/build/script/
## 修改为cmake编译方式
sed -i 's/declare CMAKE_PKG="N"/declare CMAKE_PKG="Y"/g'  build_opengauss.sh
sh -x build_opengauss.sh -m debug -3rd ${WORKSPACE}/openGauss-third_party_binarylibs
```

5. 导入环境变量
```
export PREFIX_HOME=${WORKSPACE}/openGauss-server/mppdb_temp_install
export GAUSSHOME=$PREFIX_HOME
export LD_LIBRARY_PATH=$GAUSSHOME/lib:$LD_LIBRARY_PATH
export PATH=$GAUSSHOME/bin:$PATH
```
6. 运行测试用例
```
cd ${WORKSPACE}/openGauss-server/tmp_build/
make fastcheck_ss
```

### OM+Server安装升级测试

1. 构建OM和Server包
下载openGauss-OM和openGauss-server代码
```
## OM打包，生成包在package目录下
cd ${WORKSPACE}/openGauss-OM
sh build.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs

## server打包，生成包在output目录下
cd ${WORKSPACE}/openGauss-server
sh build.sh -m release -3rd ${WORKSPACE}/openGauss-third_party_binarylibs -pkg
```

2. 安装
参考官网企业版安装进行OM方式安装：
https://docs.opengauss.org/zh/docs/latest/docs/installation/%E5%AE%89%E8%A3%85openGauss.html

主要分为两步，gs_preinstall和gs_install
```
tar -xf openGauss-xxx-xxx-om.tar.gz
cd script

## 预安装
./gs_preinstall -U omm -G omm -X /opt/cluster.xml

## 安装
su - omm
gs_install -X /opt/cluster.xml

## 查询集群状态
gs_om -t status --detail

## 卸载
gs_uninstall --delete-data

```

3. 升级
先参考企业版安装，安装一个基线版本2.0.0，基线版本从官网下载 https://opengauss.org/zh/download/，选择版本为2.0.0

安装方式和上面步骤2相同。

使用步骤1新构建的包进行升级。升级参考： https://docs.opengauss.org/zh/docs/latest/docs/UpgradeGuide/%E5%8D%87%E7%BA%A7%E5%89%8D%E5%BF%85%E8%AF%BB.html

```
## 预安装
./gs_preinstall -U omm -G omm -X /opt/cluster.xml

## 灰度升级
gs_upgradectl -t auto-upgrade -X /opt/cluster.xml --grey

## 升级提交
gs_upgradectl -t commit-upgrade  -X /opt/cluster.xml
```


