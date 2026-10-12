FROM openeuler/openeuler:20.03-lts

COPY openGauss-third_party_binarylibs_openEuler_arm.tar.gz .
COPY apache-maven-3.6.3-bin.tar.gz .
COPY OpenJDK8U-jdk_aarch64_linux_hotspot_8u222b10.tar.gz .
COPY OpenJDK8U-jdk_x64_linux_hotspot_8u222b10.tar.gz .
COPY cmake-3.19.5-Linux-aarch64.tar.gz .
COPY openEuler_aarch64.repo /etc/yum.repos.d/openEuler_aarch64.repo

ENV LANG en_US.utf8

RUN set -eux; \
    mkdir -p /usr1/build/workspace/ && \
    ln -s /usr/lib/dkms/lsb_release /usr/bin/lsb_release && \
    mv openGauss-third_party_binarylibs_openEuler_arm.tar.gz /usr1/build/workspace/openGauss-third_party_binarylibs.tar.gz && \
    mkdir /usr1/build/workspace/volume && \
    mkdir /usr1/build/workspace/openGauss && \
    mkdir /usr1/build/workspace/result && \
    mkdir /usr1/build/workspace/dependency && \
    mkdir /usr1/build/workspace/output && \
    mv apache-maven-3.6.3-bin.tar.gz /usr1/build/workspace/dependency/ && \
    mv OpenJDK8U-jdk*.tar.gz /usr1/build/workspace/dependency/ && \
    mv cmake-3.19.5-Linux-aarch64.tar.gz /usr1/build/workspace/dependency/cmake-3.19.5-Linux.tar.gz && \
    touch /usr1/build/workspace/build.log

COPY entrypoint.sh /usr/local/bin/
COPY build_3rd.sh /usr/local/bin/

RUN chmod 755 /usr/local/bin/entrypoint.sh && \
    chmod 755 /usr/local/bin/build_3rd.sh && \
    ln -s /usr/local/bin/entrypoint.sh / && \
    ln -s /usr/local/bin/build_3rd.sh /

ENTRYPOINT ["entrypoint.sh"]
