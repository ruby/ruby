require 'rinda/ring'

DRb.start_service
case ARGV.shift
when 's'
  require 'rinda/tuplespace'
  ts = Rinda::TupleSpace.new
  Rinda::RingServer.new(ts)
  $stdin.gets
when 'w'
  finger = Rinda::RingFinger.new(nil)
  finger.lookup_ring do |ts2|
    p ts2
    ts2.write([:hello, :world])
  end
when 'r'
  finger = Rinda::RingFinger.new(nil)
  finger.lookup_ring do |ts2|
    p ts2
    p ts2.take([nil, nil])
  end
end
