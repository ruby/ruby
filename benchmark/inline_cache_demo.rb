# frozen_string_literal: true
#
# Ruby Inline Cache Demo Benchmarks
# ===================================
# Demonstrates the 5 types of Ruby inline caches and their performance impact.
# Run with: gem install benchmark-ips && ruby inline_cache_demo.rb

require "benchmark/ips"

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts "=" * 60

# =============================================================================
# 1. IC (Inline Constant Cache) - opt_getconstant_path
# =============================================================================
# Caches: constant value + lexical scope (cref)
# Key:    ic->entry->ic_cref == current cref
# Source: vm_insnhelper.c - rb_vm_opt_getconstant_path()
# =============================================================================

puts "\n[IC] Inline Constant Cache"
puts "-" * 40

FIXED_CONST = 42

module ICBenchmark
  SCOPED_CONST = "hello"

  def self.read_scoped_const
    SCOPED_CONST  # IC hit: same lexical scope every call
  end
end

# IC hit: constant is defined and cref matches
# IC miss/invalidation: constant is reassigned or module is reopened

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("IC hit: constant access (same scope)") do
    ICBenchmark::SCOPED_CONST
  end

  x.report("IC hit: top-level constant") do
    FIXED_CONST
  end

  x.compare!
end

# =============================================================================
# 2. IVC (Inline Variable Cache) - getinstancevariable / setinstancevariable
# =============================================================================
# Caches: shape_id + attribute index (packed in uint64_t)
# Key:    object's shape_id == cached shape_id
# Source: vm_insnhelper.c - vm_getivar(), vm_setivar()
#
# Ruby 3.2+ uses "object shapes" - a shape is determined by the order in which
# instance variables are first assigned. Objects with identical ivar assignment
# order share the same shape_id, enabling a fast indexed lookup.
# =============================================================================

puts "\n[IVC] Inline Variable Cache (Instance Variables)"
puts "-" * 40

# Consistent shape: all objects share the same shape tree path
class ConsistentShape
  def initialize
    @x = 0
    @y = 0
    @z = 0
  end

  def read_x = @x
  def read_y = @y
  def set_x(v) = (@x = v)
end

# Inconsistent shape: conditional ivar definition causes shape branching
# shape_id will differ between objects → IVC miss on every new shape
class InconsistentShape
  def initialize(flag)
    @a = 0
    if flag
      @b = 0  # only some objects have @b → creates shape fork
    end
    @c = 0
  end

  def read_c = @c
end

obj_consistent = ConsistentShape.new
obj_a = InconsistentShape.new(true)
obj_b = InconsistentShape.new(false)

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("IVC hit: consistent shape (read)") do
    obj_consistent.read_x
  end

  x.report("IVC hit: consistent shape (write)") do
    obj_consistent.set_x(1)
  end

  # Alternating between objects with different shapes forces cache misses
  objs = [obj_a, obj_b]
  i = 0
  x.report("IVC miss: alternating shapes (read @c)") do
    objs[i & 1].read_c
    i += 1
  end

  x.compare!
end

# =============================================================================
# 3. ICVARC (Inline Class Variable Cache) - getclassvariable / setclassvariable
# =============================================================================
# Caches: rb_cvar_class_tbl_entry (global_cvar_state + cref)
# Key:    ic->entry->global_cvar_state == GET_GLOBAL_CVAR_STATE()
#         AND ic->entry->cref == current cref
# Source: vm_insnhelper.c - vm_getclassvariable()
#
# ruby_vm_global_cvar_state is incremented whenever a new class variable
# is defined in a subclass that "overshadows" an ancestor's cvar.
# =============================================================================

puts "\n[ICVARC] Inline Class Variable Cache"
puts "-" * 40

class CVarBase
  @@counter = 0

  def self.read_counter = @@counter
  def self.inc_counter  = (@@counter += 1)
end

class CVarChild < CVarBase
  # Does NOT define its own @@counter → inherits from CVarBase
  # ICVARC stays valid as long as global_cvar_state doesn't change
  def self.read_inherited = @@counter
end

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("ICVARC hit: read cvar (stable hierarchy)") do
    CVarBase.read_counter
  end

  x.report("ICVARC hit: write cvar (same class)") do
    CVarBase.inc_counter
  end

  x.compare!
end

# =============================================================================
# 4. ISE (Inline Storage Entry) - once instruction
# =============================================================================
# Caches: result of a code block that should run exactly once.
# Key:    is->once.running_thread == RUNNING_THREAD_ONCE_DONE (sentinel)
# Source: vm_insnhelper.c - vm_once_dispatch()
#
# Used by: /regex/ literals (compiled once), string frozen with -w, BEGIN {}
# The cache is NEVER invalidated after being set.
# =============================================================================

puts "\n[ISE] Inline Storage Entry (once)"
puts "-" * 40

def method_with_once_regex(str)
  # /foo+/ is compiled once and reused on every call
  str.match?(/foo+bar/)
end

def method_with_fresh_regex(str)
  # Constructed each call to simulate "no cache"
  pattern = Regexp.new("foo+bar")
  str.match?(pattern)
end

TEST_STR = "foooobar"

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("ISE hit: /regex/ literal (compiled once)") do
    method_with_once_regex(TEST_STR)
  end

  x.report("ISE miss: Regexp.new (compiled every call)") do
    method_with_fresh_regex(TEST_STR)
  end

  x.compare!
end

# =============================================================================
# 5. CC (Call Cache) - send/opt_send_without_block
# =============================================================================
# Caches: receiver class (klass) + callable method entry (cme) + call handler
# Key:    vm_cc_class_check(cc, CLASS_OF(recv))
#         AND !METHOD_ENTRY_INVALIDATED(vm_cc_cme(cc))
# Source: vm_insnhelper.c - vm_search_method_fastpath()
#
# The CC is stored per call site (CALL_DATA). When the receiver's class
# matches the cached class and the method entry is still valid → fast path.
# Invalidated by: define_method, include, prepend, remove_method, undef_method.
# =============================================================================

puts "\n[CC] Call Cache (Method Dispatch)"
puts "-" * 40

class MonomorphicTarget
  def greet = "hello"
end

class PolymorphicA
  def greet = "hello from A"
end

class PolymorphicB
  def greet = "hello from B"
end

class PolymorphicC
  def greet = "hello from C"
end

mono = MonomorphicTarget.new

poly_objs = [PolymorphicA.new, PolymorphicB.new, PolymorphicC.new]

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("CC hit: monomorphic call site (1 receiver class)") do
    mono.greet
  end

  # Megamorphic: 3+ different receiver classes at same call site
  # CC can only hold 1 entry → misses on every class rotation
  i = 0
  x.report("CC miss: megamorphic call site (3 receiver classes)") do
    poly_objs[i % 3].greet
    i += 1
  end

  x.compare!
end

puts "\nDone."
