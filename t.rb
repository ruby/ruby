#! /usr/bin/ruby
tc = Class.new(Time)
tc.inspect
t = tc.now
proc do
  $SAFE=4
  t.gmtime
end.call
