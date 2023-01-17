FROM gliderlabs/logspout:master

ENTRYPOINT ["/monitor.sh"]

ADD monitor.sh /
