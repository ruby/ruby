# -*- encoding: euc-jp -*-
=begin
 distributed Ruby --- dRuby Sample Client -- chasen client
 	Copyright (c) 1999-2001 Masatoshi SEKI
=end

require 'drb/drb'

there = ARGV.shift || raise("usage: #{$0} <server_uri>")
DRb.start_service
dhasen = DRbObject.new(nil, there)

print dhasen.sparse("�����ϡ���ŷ�ʤꡣ", "-F", '(%BB %m %M)\n', "-j")
print dhasen.sparse("�����ϡ���ŷ�ʤꡣ", "-F", '(%m %M)\n')
