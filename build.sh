#!/bin/sh
set -e
apk add --update go build-base git mercurial ca-certificates
cd /tmp
git clone https://github.com/Hossy/looplab-logspout-logstash.git
cp -rf looplab-logspout-logstash/src-override/* /src
cd /src
go mod edit -replace invalid.url/looplab/logspout-logstash=/tmp/looplab-logspout-logstash
go build -ldflags "-X main.Version=$1" -o /bin/logspout
apk del go git mercurial build-base
rm -rf /root/go /var/cache/apk/*

# backwards compatibility
ln -fs /tmp/docker.sock /var/run/docker.sock
