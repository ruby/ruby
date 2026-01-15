#!/bin/bash
set -ex
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

cat /etc/hosts
ruby -e "hosts = File.read('/etc/hosts').sub(/^::1\s*localhost.*$/, ''); File.write('/etc/hosts', hosts)"
cat /etc/hosts
