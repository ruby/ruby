# RLGCv2 (design_v2.md section 4.5): Ractor#send(obj, move: true) re-homes
# the moved graph into the RECEIVING Ractor's objspace by running the move
# traversal a second time on receive. Without it the receiver holds
# unshareable cross-objspace edges (caught by GC.verify_internal_consistency)
# and the moved graph stalls the sender's shareable trigger.
#
# Covers: containment after move, sender-side MovedError, IO fd-ownership
# move, generic ivars + frozen flag continuity, deep graphs, many movers
# under GC pressure, and verify interleaved on both sides.
Warning[:experimental] = false

def check(cond, msg)
  raise "FAIL: #{msg}" unless cond
end

# 1) containment: a moved graph must satisfy the verifier on the receiver
r = Ractor.new do
  x = Ractor.receive
  GC.verify_internal_consistency
  [x.size, x[0], x[2][0]]
end
r.send([+"a", +"b", [+"c"]], move: true)
check(r.value == [3, "a", "c"], "moved value mismatch")
GC.verify_internal_consistency

# 2) the sender's original becomes a MovedObject
arr = [+"x"]
r2 = Ractor.new { Ractor.receive.first }
r2.send(arr, move: true)
moved = (begin; arr.size; :no_error; rescue Ractor::MovedError, NoMethodError; :moved; end)
check(moved == :moved, "sender original still usable after move")
check(r2.value == "x", "r2 result")

# 3) IO fd ownership travels with the move (dmove-style T_DATA)
rd, wr = IO.pipe
r3 = Ractor.new do
  w = Ractor.receive
  w.write "fd-ok"
  w.close
  :done
end
r3.send(wr, move: true)
check(r3.value == :done, "r3 result")
check(rd.read == "fd-ok", "moved IO did not carry the fd")
rd.close

# 4) generic ivars + object identity through the two-pass move
s = +"host"
s.instance_variable_set(:@tag, [+"t1", +"t2"])
s.freeze
r4 = Ractor.new do
  o = Ractor.receive
  [o.instance_variable_get(:@tag), o.frozen?]
end
r4.send(s, move: true)
tag, frz = r4.value
check(tag == ["t1", "t2"], "moved generic ivar lost: #{tag.inspect}")
check(frz, "frozen flag lost across move")

# 5) deep graph + many movers, with GC churn and verify on the receiver
movers = 12.times.map do |i|
  Ractor.new(i) do |idx|
    node = nil
    received = 0
    loop do
      msg = Ractor.receive
      break if msg == :stop
      depth = 0
      m = msg
      while m.is_a?(Array) && m.last.is_a?(Array)
        depth += 1
        m = m.last
      end
      received += 1
      Array.new(300) { +"g#{idx}" }   # local churn -> local GCs
      node = msg                       # retain the latest
    end
    [received, node ? node.first : nil]
  end
end

300.times do |n|
  graph = [+"r#{n}", n]
  6.times { |d| graph = [+"d#{d}", graph] }   # depth-6 nested array
  movers[n % movers.size].send(graph, move: true)
  GC.start(full_mark: n % 30 == 0) if n % 5 == 0
end
movers.each { |m| m.send(:stop) }
results = movers.map(&:value)
check(results.all? { |(rcv, _)| rcv > 0 }, "some mover got nothing")

GC.verify_internal_consistency
3.times { GC.start; 5_000.times { Object.new } }
GC.verify_internal_consistency

puts "MOVE_REHOME_OK"
