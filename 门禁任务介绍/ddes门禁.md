# ddes任务门禁介绍

ddes的门禁任务有3个，分别是CBB，DSS，DMS。



## 1、CBB门禁介绍

CBB门禁主要维护CBB编译功能



### CBB编译功能测试

编译工具：cmake或make，建议使用cmake

1.下载cbb源码

2.下载三方库

3.编译源码

```shell
cd ${WORKSPACE}/CBB/build/linux/opengauss
sh -x build.sh -3rd ${third_party_binarylibs_path} -m Release -t cmake
```



## 2、DSS门禁介绍

DSS门禁主要是维护DSS编译功能



### DSS编译功能测试

编译工具：cmake或make，建议使用cmake

1.下载cbb，dss源码

2.下载三方库

3.编译cbb源码

```shell
cd ${WORKSPACE}/CBB/build/linux/opengauss
sh -x build.sh -3rd ${third_party_binarylibs_path} -m Release -t cmake
```

4.编译dss源码

```shell
cd ${WORKSPACE}/DSS/build/linux/opengauss
sh -x build.sh -3rd ${third_party_binarylibs_path} -m ReleaseDsstest -t cmake
```



## 3、DMS门禁介绍

DMS门禁主要是维护DMS编译功能



### DMS编译功能测试

编译工具：cmake或make，建议使用cmake

1.下载cbb，dms源码

2.下载三方库

3.编译cbb源码

```shell
cd ${WORKSPACE}/CBB/build/linux/opengauss
sh -x build.sh -3rd ${third_party_binarylibs_path} -m Release -t cmake
```

4.编译dms源码

```shell
cd ${WORKSPACE}/DMS/build/linux/opengauss
sh -x build.sh -3rd ${third_party_binarylibs_path} -m Release -t cmake
```