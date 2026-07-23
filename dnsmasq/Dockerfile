FROM alpine:3.21
RUN apk add --no-cache dnsmasq
CMD ["dnsmasq", "-k", "--conf-file=/etc/dnsmasq.d/harbour.conf", "--no-daemon"]
