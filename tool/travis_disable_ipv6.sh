#!/bin/bash
set -ex
ip a
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1
ip a

cat /etc/hosts
sudo ruby -e "hosts = File.read('/etc/hosts').sub(/^::1\s*localhost.*$/, ''); File.write('/etc/hosts', hosts)"
cat /etc/hosts
