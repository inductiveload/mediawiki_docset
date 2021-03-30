#! /usr/bin/env bash
#
set -e
set -x

BRANCH=${1:-master}

REPO="https://gerrit.wikimedia.org/r/mediawiki/core.git"
LOCALREPO="mediawiki-core"

DOCSET_NAME=MediaWiki
DOCSET=${DOCSET_NAME}.docset

DOX_REPO="https://github.com/doxygen/doxygen.git"
DOX_LOCALREPO="doxygen"

DOX_EXTRA_CONF="doxygen-config.conf"

DOC_OUTPUT="docs/html"


if [[ "$BRANCH" == "master" ]]
then
    DOCKER_EXTRAS=$(pwd)/docker-master
else
    DOCKER_EXTRAS=$(pwd)/docker-1.38
fi

rm -rf $DOCSET

git clone "$REPO" "$LOCALREPO" 2> /dev/null || git -C "$LOCALREPO" pull

git clone "$DOX_REPO" "$DOX_LOCALREPO" 2> /dev/null || git -C "$DOX_LOCALREPO" fetch
cd "$DOX_LOCALREPO"
mkdir -p build
git checkout master
cd ..

cd "$LOCALREPO"

# dump any old changes
git checkout .

git checkout "$BRANCH"
git submodule update --init

cp ../.env .env

# add the uid and gid
echo "
MW_DOCKER_UID=$(id -u)
MW_DOCKER_GID=$(id -g)" >> .env

cp "${DOCKER_EXTRAS}"/* .

# replace the image in the override Dockerfile - this must match the docker-compose.yml
IMAGE=$(grep -P '(?<=image:).*fpm\S+' docker-compose.yml -o | sed 's/^ //')
echo "Using image: ${IMAGE}"

cp ../Dockerfile .
sed -i "s|<<IMAGE>>|${IMAGE}|" Dockerfile


rm -f LocalSettings.php
rm -rf cache

cat ../$DOX_EXTRA_CONF >> maintenance/Doxyfile

# extract the version from the PHP
MW_VERSION=$(grep "^define(.*MW_VERSION" includes/Defines.php | sed -E "s/.*'(1\.[^']*)'.*/\1/")
MW_COMMIT=$(git rev-parse --short HEAD)
# interpolate MW version into Doxyfile
sed -i "s|<<MW_VERSION>>|${MW_VERSION} ($MW_COMMIT)|" maintenance/Doxyfile

docker-compose down --remove-orphans || true

# # start mediawiki
docker-compose build
docker-compose up -d

# first build a doxygen that can handle mediawiki
docker-compose exec mediawiki bash -c "cd /doxygen/build &&
        cmake -G 'Unix Makefiles' -Denlarge_lex_buffers=16777216 -Dbuild_parse=ON .. &&
        make -j$(nproc)"

# install a fresh MediaWiki
docker-compose exec mediawiki composer update
docker-compose exec mediawiki /bin/bash /docker/install.sh

# use our phat buffer doxygen to generate the docs
docker-compose exec mediawiki php maintenance/mwdocgen.php --doxygen /doxygen/build/bin/doxygen


docker-compose exec mediawiki doxygen2docset --doxygen "${DOC_OUTPUT}" --docset .

cd ..
rm -rf "${DOCSET}"
mv "${LOCALREPO}/${DOCSET}" "${DOCSET}"

# turn on javascript and other good stuff
sed -E -i 's!</(dict|plist)>!!' "${DOCSET}/Contents/Info.plist"
cat plist_extra.xml >> "${DOCSET}/Contents/Info.plist"


cp icons/*.png "${DOCSET}"

tar -cvzf "${DOCSET_NAME}.tgz" "${DOCSET}"