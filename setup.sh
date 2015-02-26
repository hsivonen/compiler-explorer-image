#!/bin/bash

set -ex

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ "$1" != "--updated" ]]; then
    git --work-tree ${DIR} pull
    pwd
    exec bash ${BASH_SOURCE[0]} --updated
    exit 0
fi

miraclehook() {
    rm -rf roms
    mkdir -p roms
    rm -f miracle-roms.tar.gz
    /root/s3cmd/s3cmd get s3://xania.org/miracle-roms.tar.gz
    tar zxf miracle-roms.tar.gz
    rm miracle-roms.tar.gz
    chown -R ubuntu roms
}

get_or_update_repo() {
    local USER=$1
    local REPO=$2
    local BRANCH=$3
    local DIR=$4
    if [[ ! -e ${DIR} ]]; then
        su -c "git clone --branch ${BRANCH} ${REPO} ${DIR}" "${USER}"
    else
        su -c "cd ${DIR}; git pull && git checkout ${BRANCH}" "${USER}"
    fi
    pushd ${DIR}
    $5
    grep 'dist:' Makefile && su -c "make dist" ${USER}
    popd
}

PTRAIL='/etc/rsyslog.d/99-papertrail.conf'
if [[ ! -f "${PTRAIL}" ]]; then
    echo '*.*          @logs2.papertrailapp.com:34474' > "${PTRAIL}"
    service rsyslog restart
    pushd /tmp
    curl -sL 'https://github.com/papertrail/remote_syslog2/releases/download/v0.13/remote_syslog_linux_amd64.tar.gz' | tar zxf -
    cp remote_syslog/remote_syslog /usr/local/bin/
    cat > /etc/log_files.yml << EOF
files:
  - /var/log/nginx/*.log
  - /var/log/nginx/*.err
destination:
  host: logs2.papertrailapp.com
  port: 34474
  protocol: tls
EOF
    docker pull gliderlabs/logspout:latest
    popd
fi

docker rm logspout || true
docker run --name logspout -d -v=/var/run/docker.sock:/tmp/docker.sock gliderlabs/logspout syslog://logs2.papertrailapp.com:34474

apt-get -y update
apt-get -y upgrade --force-yes
apt-get -y install git make nodejs-legacy npm docker.io libpng-dev m4 \
    python-markdown python-pygments python-pip perl
pip install pytz python-dateutil

if ! grep ubuntu /etc/passwd; then
    useradd ubuntu
    mkdir /home/ubuntu
    chown ubuntu /home/ubuntu
fi

mkdir -p /home/ubuntu/.ssh
cp /root/.ssh/known_hosts /root/.ssh/id_rsa* /home/ubuntu/.ssh/
chown -R ubuntu /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/id_rsa

cd /home/ubuntu/
get_or_update_repo root git@github.com:s3tools/s3cmd.git master /root/s3cmd
get_or_update_repo ubuntu git://github.com/mattgodbolt/jsbeeb.git release jsbeeb
get_or_update_repo ubuntu git://github.com/mattgodbolt/jsbeeb.git master jsbeeb-beta
get_or_update_repo ubuntu git://github.com/mattgodbolt/Miracle master miracle miraclehook
get_or_update_repo ubuntu git@github.com:mattgodbolt/blog.git master blog
get_or_update_repo ubuntu git@github.com:mattgodbolt/blog.git new_blog blog-beta

if ! egrep '^DOCKER_OPTS' /etc/default/docker.io >/dev/null; then
    echo 'DOCKER_OPTS="--restart=false"' >> /etc/default/docker.io
fi
cp /gcc-explorer-image/init/* /etc/init/
docker pull mattgodbolt/gcc-explorer
docker pull dockerfile/nginx
[ "$UPSTART_JOB" != "gcc-explorer" ] && service gcc-explorer start || true
