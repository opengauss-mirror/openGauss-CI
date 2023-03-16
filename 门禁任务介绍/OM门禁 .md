
### openGauss-OM仓库门禁说明

openGauss-OM门禁主要看护安装和升级功能，集群部署方式为一主一备。

在运行OM门禁时候，首先会下载对应分支的OM和Server代码，然后进行构建打包。

1. 对构建包进行安装，测试主备安装是否正常。

2. 安装一个2.0.0版本作为基线包，在升级到当前新构建的版本测试升级功能。

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


