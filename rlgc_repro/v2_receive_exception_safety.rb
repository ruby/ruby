# RLGCv2 (review A-6): exception safety of the receive / move paths.
#
# 1. A raising marshal_load hook on the receiver used to leave the
#    in-flight materializing slot set: the containment verifier stayed
#    disabled for the Ractor's remaining life, the next receive tripped a
#    VM_ASSERT, and after the Ractor died its zombie ractor_sync_mark kept
#    marking a snapshot the sender had already collected (UAF).
# 2. A nested Ractor.receive from inside marshal_load used to overwrite
#    the single slot; completing the inner receive reset it to Qfalse and
#    the OUTER snapshot lost its only re-pin root across a global GC.
# 3. A move: of a graph with an unmovable child used to husk the movable
#    siblings captured before the raise -- data destroyed, courier leaked.
#    With the preflight the graph must be intact after the error.
Warning[:experimental] = false

# --- custom-marshal payloads ---------------------------------------------
# A plain T_OBJECT is copied natively (marshal hooks are NOT consulted);
# the Marshal fallback runs only for natively-uncopyable types, e.g.
# T_DATA. A Time subclass is T_DATA with _dump/_load support, so its
# _load runs on the RECEIVER -- the hook we need.
class BoomOnLoad < Time
  def self._load(_) # runs on the RECEIVER
    raise "boom from _load"
  end
end

class NestedReceive < Time
  def self._load(_)
    # nested receive inside the outer materialize
    Ractor.current[:inner] = Ractor.receive
    NestedReceive.at(0)
  end
end

# 1) raising marshal_load: receiver must survive, keep receiving, verify
r = Ractor.new do
  got = []
  10.times do
    begin
      got << Ractor.receive.class.name
    rescue => e
      got << "raised:#{e.message}"
    end
    GC.start
    GC.verify_internal_consistency
  end
  got
end
10.times do |i|
  r.send(i.even? ? BoomOnLoad.at(i) : { plain: i })
  GC.start # churn the sender snapshot side
end
got = r.value
raise "no raise seen: #{got.inspect}" unless got.grep(/raised:boom/).size == 5
raise "receiver corrupted: #{got.inspect}" unless got.grep(/Hash/).size == 5

# 2) nested receive inside _load (outer snapshot must survive the inner
#    receive + global GCs in between)
r2 = Ractor.new do
  outer = Ractor.receive     # materialize runs _load -> nested receive
  [outer.class.name, Ractor.current[:inner]]
end
r2.send(NestedReceive.at(42))
5.times { GC.start; 200.times { Object.new } } # global cycles while nested-pending
r2.send(:inner_payload)
klass, inner = r2.value
raise "nested receive broke: #{klass}/#{inner.inspect}" unless
  klass == "NestedReceive" && inner == :inner_payload

# 3) move preflight: failed move must leave the graph intact
r3 = Ractor.new { Ractor.receive }
movable = ["keep me", { k: "v" }]
graph = [movable, Mutex.new] # Mutex: T_DATA, neither movable nor shareable
begin
  r3.send(graph, move: true)
  raise "move unexpectedly succeeded"
rescue Ractor::Error => e
  raise "wrong error #{e.message}" unless e.message =~ /can not move/
end
# graph must be untouched (no husked siblings)
raise "sibling husked!" unless movable[0] == "keep me" && movable[1] == { k: "v" }
raise "array husked!" unless graph.size == 2
r3.send(:done)
raise unless r3.value == :done

GC.start
GC.verify_internal_consistency
puts "OK v2_receive_exception_safety"
