#!/bin/bash

mkdir -p /data/db
chown vagrant -R /data

# Change "us" to another country if you live there
COUNTRY=us
if ! grep -q $COUNTRY'\.archive\.ubuntu\.com' /etc/apt/sources.list; then
    sed -i'' -e 's/[a-z]*\.archive\.ubuntu\.com/'$COUNTRY'.archive.ubuntu.com/g' /etc/apt/sources.list
fi

if [ ! -f /var/cache/apt/pkgcache.bin ] || /usr/bin/find /etc/apt/* -cnewer /var/cache/apt/pkgcache.bin | /bin/grep . > /dev/null; then
    apt-get update
fi
apt-get install -y \
    bison \
    build-essential \
    chrpath \
    cmake \
    curl \
    g++-4.7 \
    git-core \
    libaio-dev \
    libdb-dev \
    libncurses5-dev \
    scons \
    valgrind \
    zlib1g-dev

touch .bash_profile
if ! grep -q 'gcc-4.7' .bash_profile; then
    echo "CC=gcc-4.7" >> .bash_profile
    echo "CXX=g++-4.7" >> .bash_profile
    echo "export CC CXX" >> .bash_profile
fi

function git_get {
    if [[ -d $1 ]]; then
        pushd $1
        git pull
        errorcode=$?
        if [[ $errorcode != 0 ]]; then
            echo "error $errorcode running git pull" 1>&2
            exit $errorcode
        fi
        popd
    else
        git clone http://github.com/Tokutek/$1
        errorcode=$?
        if [[ $errorcode != 0 ]]; then
            echo "error $errorcode running git clone" 1>&2
            exit $errorcode
        fi
    fi
}

git_get mongo
git_get backup-community
git_get ft-index
pushd ft-index/third_party
git_get jemalloc
popd

git_get ft-engine

cat <<EOF >build-tokumx.sh
#!/bin/bash

set -e

. \$HOME/.bash_profile

mkdir -p backup-community/backup/opt
pushd backup-community/backup/opt
cmake \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_INSTALL_PREFIX=~/mongo/src/third_party/tokubackup \
    -D HOT_BACKUP_LIBNAME=HotBackup \
    -D BACKUP_HAS_PARENT=OFF \
    ..
cmake --build . --target install
popd

mkdir -p ft-index/opt
pushd ft-index/opt
cmake \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_INSTALL_PREFIX=~/mongo/src/third_party/tokukv \
    -D BUILD_TESTING=OFF \
    -D USE_VALGRIND=OFF \
    -D USE_BDB=OFF \
    -D TOKU_DEBUG_PARANOID=OFF \
    -D USE_CTAGS=OFF \
    -D USE_ETAGS=OFF \
    -D USE_CSCOPE=OFF \
    -D USE_GTAGS=OFF \
    ..
cmake --build . --target install
popd

cd mongo
scons --cc=gcc-4.7 --cxx=g++-4.7 --mute --release dist
EOF
chmod +x build-tokumx.sh

chown vagrant -R mongo backup-community ft-index ft-engine build-tokumx.sh .bash_profile

touch /etc/motd.tail
if ! grep -q Tokutek /etc/motd.tail; then
    cat <<EOF >> /etc/motd.tail

Welcome to the Tokutek build machine!


To build a TokuMX release, please make sure each repository (ft-index,
mongo, and backup-community) has the right branch or tag checked out.  For
example, to build the head of the 1.1 branch, you can do this:

 $ (cd ft-index; git checkout releases/tokumx-1.1)
 $ (cd backup-community; git checkout releases/tokumx-1.1)
 $ (cd mongo; git checkout releases/tokumx-1.1)

Then, just run './build-tokumx.sh'.  It'll build everything with the right
optimizations.


To build a TokuDB release, please use ~/ft-engine/scripts/make.mysql.bash.
You can run ~/ft-engine/scripts/make.mysql.bash --help to see options.
For a simple MySQL or MariaDB build, try one of these:

 $ ~/ft-engine/scripts/make.mysql.bash --cc=gcc-4.7 --cxx=g++-4.7 --mysqlbuild=mysql-5.5.30-tokudb-7.0.4-linux-x86_64
 $ ~/ft-engine/scripts/make.mysql.bash --cc=gcc-4.7 --cxx=g++-4.7 --mysqlbuild=mariadb-5.5.30-tokudb-7.0.4-linux-x86_64

EOF
fi
