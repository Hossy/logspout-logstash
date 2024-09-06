FROM ghcr.io/hossy/logspout:master

ENTRYPOINT ["/monitor.sh"]

ADD monitor.sh /
