# frozen_string_literal: true

# Reproducer/probe for dynamic T_OBJECT slot capacity being narrowed before
# shape code clamps it. Run from build/ with:
#
#   ./ruby --yjit --yjit-call-threshold=1 ../repro_yjit_shape_capacity.rb
#
# A crashing YJIT run depends on the allocator returning a slot whose capacity
# gets truncated to a smaller attr_index_t value. This script first checks the
# underlying invariant directly so it is useful even when it does not crash.

require "objspace"

POINTER_SIZE = [0].pack("J").bytesize
RBASIC_SIZE = GC::INTERNAL_CONSTANTS.fetch(:RBASIC_SIZE)

def dump_hash(obj)
  ObjectSpace.dump(obj).then do |dump|
    require "json"
    JSON.parse(dump)
  end
end

def object_slot_capacity(obj)
  dump = dump_hash(obj)
  (dump.fetch("slot_size") - RBASIC_SIZE) / POINTER_SIZE
end

def shape_capacity(obj)
  return RubyVM::Shape.of(obj).capacity if defined?(RubyVM::Shape)

  # Without SHAPE_DEBUG, infer only from behavior below.
  nil
end

def embedded?(obj)
  dump_hash(obj).key?("embedded")
end

shape_max_fields = if defined?(RubyVM::Shape::SHAPE_MAX_FIELDS)
  RubyVM::Shape::SHAPE_MAX_FIELDS
else
  126
end

class ShapeCapacityProbe
  def read_last
    @v_last
  end
end

# Force future ShapeCapacityProbe instances to request the largest normal
# T_OBJECT slot that shapes are supposed to support.
seed = ShapeCapacityProbe.new
shape_max_fields.times do |i|
  seed.instance_variable_set(:"@seed_#{i}", i)
end

probe = ShapeCapacityProbe.new
slot_capacity = object_slot_capacity(probe)
root_capacity = shape_capacity(probe)
expected_capacity = [slot_capacity, shape_max_fields].min

puts "slot_capacity=#{slot_capacity} expected_shape_capacity=#{expected_capacity} shape_capacity=#{root_capacity.inspect}"
puts "initial=#{ObjectSpace.dump(probe).strip}"

if root_capacity && root_capacity < expected_capacity
  abort "BUG: root shape capacity #{root_capacity} is smaller than actual supported capacity #{expected_capacity}"
end

# Behavior-only check for non-SHAPE_DEBUG builds: fill up to the capacity that
# should be embeddable in this slot. A bad truncated root capacity externalizes
# this object before the slot is full.
expected_capacity.times do |i|
  name = i == expected_capacity - 1 ? :@v_last : :"@v_#{i}"
  probe.instance_variable_set(name, i)
end

puts "filled=#{ObjectSpace.dump(probe).strip}"

unless embedded?(probe)
  abort "BUG: object externalized after #{expected_capacity} ivars even though its slot can embed them"
end

if RubyVM.const_defined?(:YJIT) && RubyVM::YJIT.enabled?
  expected = expected_capacity - 1
  20_000.times do
    value = probe.read_last
    abort "BUG: YJIT read wrong value #{value.inspect}, expected #{expected.inspect}" unless value == expected
  end
  puts "YJIT read stress passed"
else
  warn "YJIT is not enabled; rerun with --yjit --yjit-call-threshold=1 for the JIT stress path."
end

puts "No capacity mismatch reproduced on this build."
