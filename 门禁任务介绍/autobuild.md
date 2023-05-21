# autobuild

autobuild是每日构建的一些任务，下面就简单介绍下



## 1、portal

portal是用java语言写的，是一个集成了全量迁移、增量迁移、反向迁移、数据校验的工具，运行于linux系统。

**构建过程**

1. 下载portal源码

   ```shell
   git clone https://gitee.com/opengauss/openGauss-migration-portal.git
   ```

2. 下载tools

   ```shell
   portal_package_name=PortalControl-5.0.0.tar.gz
   chameleon=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/chameleon/chameleon-5.0.0-py3-none-any.whl
   datacheck=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/openGauss-datachecker-performance-5.0.0.tar.gz
   kafka=https://mirrors.tuna.tsinghua.edu.cn/apache/kafka/3.2.3/kafka_2.13-3.2.3.tgz
   confluent=https://packages.confluent.io/archive/5.5/confluent-community-5.5.1-2.12.zip
   debezium_connector_mysql=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/replicate-mysql2openGauss-5.0.0.tar.gz
   debezium_connector_opengauss=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/replicate-openGauss2mysql-5.0.0.tar.gz
   
   wget $chameleon -P ${workspace}/openGauss-migration-portal/portal/pkg/chameleon
   wget $datacheck -P ${workspace}/openGauss-migration-portal/portal/pkg/datacheck
   wget $kafka -P ${workspace}/openGauss-migration-portal/portal/pkg/debezium --no-check-certificate
   wget $confluent -P ${workspace}/openGauss-migration-portal/portal/pkg/debezium --no-check-certificate
   wget $debezium_connector_mysql -P ${workspace}/openGauss-migration-portal/portal/pkg/debezium
   wget $debezium_connector_opengauss -P ${workspace}/openGauss-migration-portal/portal/pkg/debezium
   ```

3. mvn打包

   ```shell
   mvn clean package -Dmaven.test.skip=true
   ```

4. 上传至obs

   ```shell
   /home/obsutil cp ${package_name} ${obs_upload_path}/
   ```

   

## 2、dbmind

DBMind作为openGauss数据库的一部分，为openGauss数据库提供了自动驾驶能力，是一款领先的开源数据库自治运维平台。通过DBMind, 您可以很容易地发现数据库的问题，同时可以实现秒级的数据库问题根因分析。

**构建过程**

1. 下载dbmind源码

   ```shell
   git clone https://gitee.com/opengauss/openGauss-DBMind.git
   ```

2. 打包

    ```shell
    cd ${WORKSPACE}/dbmind || exit
    sh package.sh
    ```

3. 上传至ods

    ```shell
    /home/obsutil cp ${package_name} ${obs_upload_path}/${dbs_dest}/
    ```

