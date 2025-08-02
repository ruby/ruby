require 'etc'

pw = Etc.getpwuid(`id -u`.strip.to_i)
pp pw
p pw.gid
