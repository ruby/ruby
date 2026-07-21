# RLGCv2: GC.verify_internal_consistency under multi-objspace state.
#
# The verifier asserts (gc/default/default.c, gc.c check_shareable_i):
#  * shareable -> unshareable edges carry the target's shref record
#  * shref bit only ever names an unshareable; the shareable bit
#    mirrors FL_SHAREABLE; T_NONE slots carry no pin bits
#  * containment: an unshareable never references a foreign unshareable
#  * the calling Ractor's exact roots are scoped (own / shareable /
#    shref'd in-flight payloads)
#
# This script manufactures every checked edge shape, then runs the
# verifier from main and from workers, interleaved with local and
# global GCs.
Warning[:experimental] = false

class CIvarHost            # shareable class, unshareable class-ivar values
  @blob = +"unshareable ivar value"
  @list = [+"a", +"b"]
  def self.touch = (@blob << "x"; @list << +"c"; @list.shift)
end

module ConstHome
  BLOB = +"unshareable const value"   # const table s->u (shref)
  def self.read = BLOB.size           # fills an inline constant cache
end

obj = Object.new
def obj.singleton_method_here = 42    # singleton class (shareable) -> attached obj (u)

UnshProc = Class.new
UnshProc.define_method(:dm) { 7 }     # bmethod cme -> proc

shared_graph = Ractor.make_shareable([1, [2, 3], "frozen"].freeze)

GC.verify_internal_consistency        # single-world warmup

# Single-world compaction must carry the pin bitmaps with each moved
# object (gc_move): losing them would silently disarm the shareable pin
# / shref record once the world turns multi-objspace.
GC.compact
GC.verify_internal_consistency
r0 = Ractor.new { :post_compact }
raise unless r0.value == :post_compact
GC.verify_internal_consistency

workers = 6.times.map do |i|
  Ractor.new(i, shared_graph) do |idx, graph|
    local = Array.new(1000) { |j| "w#{idx}-#{j}" }
    20.times do |round|
      local.each { |s| s << "." if s.size < 64 }
      GC.start(full_mark: round.even?)
      GC.verify_internal_consistency
      Ractor.yield nil if false
    end
    [idx, local.size, graph.size]
  end
end

40.times do |round|
  CIvarHost.touch
  ConstHome.read
  obj.singleton_method_here
  UnshProc.new.dm
  GC.verify_internal_consistency
  GC.start(full_mark: false)
  GC.verify_internal_consistency
  if round % 10 == 0
    GC.start   # global cycle
    GC.verify_internal_consistency
  end
end

vals = workers.map(&:value)
raise "worker results" unless vals.all? { |(_, n, g)| n == 1000 && g == 3 }

# zombies + orphans, then verify again
4.times { r = Ractor.new { :z }; 10.times { break if r.inspect =~ /terminated/; sleep 0.01 }; r = nil }
3.times { GC.start }
1000.times { Object.new }
GC.verify_internal_consistency
GC.start
GC.verify_internal_consistency

puts "VERIFY_CONSISTENCY_OK"
