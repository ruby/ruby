=begin
 distributed Ruby --- Queue
 	Copyright (c) 1999-2000 Masatoshi SEKI
=end

require 'drb/drb'

DRb.start_service(nil, Thread::Queue.new)
puts DRb.uri
DRb.thread.join

