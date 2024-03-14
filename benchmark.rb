#!/usr/bin/ruby

require "benchmark/ips"

class SlowlyHashed
  attr_reader :i
  
  def initialize(i)
    @i = i
  end
  
  def hash
    sleep(0.00001) # Dummy load to slow this down
    [@i].hash
  end
  
  def eql?(other)
    @i == other.i
  end
end

unless Set.public_method_defined?(:fast_add?)
  puts <<~MSG
    The new `add?` implementation isn't available.
    Perhaps you're running this benchmark with the wrong Ruby?
  MSG
    
  exit(1)
end

class Set
  # Original implementation from before this PR
  # https://github.com/ruby/ruby/blob/c976cb5/lib/set.rb#L517-L525
  def original_add?(o)
    add(o) unless include?(o)
  end
end

GC.disable

puts "YJIT enabled? #{RubyVM::YJIT.enabled?}\n\n"

puts "Benchmarking with SlowlyHashed objects, all being new:"
Benchmark.ips do |x|
  x.config(warmup: 1, time: 5)
  x.report("Original Set#add?") do |times|
      i = 0
      
      s = Set.new
      while (i += 1) < times
        s.original_add?(SlowlyHashed.new(i))
      end
  end
    
  x.report("Improved Set#add?") do |times|
    i = 0
    
    s = Set.new
    while (i += 1) < times
      s.fast_add?(SlowlyHashed.new(i))
    end
  end  
  
  x.compare!
end


puts "Benchmarking with SlowlyHashed objects, all being pre-existing:"
Benchmark.ips do |x|
  x.config(warmup: 1, time: 5)
  x.report("Original Set#add?") do |times|
      i = 0
      
      o = SlowlyHashed.new(0)
      s = Set[o]
      while (i += 1) < times
        s.original_add?(o)
      end
  end
  
  x.report("Improved Set#add?") do |times|
    i = 0
    
    o = SlowlyHashed.new(0)
    s = Set[o]
    while (i += 1) < times
      s.fast_add?(o)
    end
  end  
  
  x.compare!
end

puts "Benchmarking with ints, all being new:"
Benchmark.ips do |x|
  x.config(warmup: 1, time: 5)
  x.report("Original Set#add?") do |times|
      i = 0
      
      s = Set.new
      while (i += 1) < times
        s.original_add?(i)
      end
  end
  
  x.report("Improved Set#add?") do |times|
    i = 0
    
    s = Set.new
    while (i += 1) < times
      s.fast_add?(i)
    end
  end
  
  
  x.compare!
end


puts "Benchmarking with all ints, all being pre-existing:"
Benchmark.ips do |x|
  x.config(warmup: 1, time: 5)
  x.report("Original Set#add?") do |times|
      i = 0
      
      s = Set[123]
      while (i += 1) < times
        s.original_add?(123)
      end
  end
  
  x.report("Improved Set#add?") do |times|
    i = 0
    
    s = Set[123]
    while (i += 1) < times
      s.fast_add?(123)
    end
  end
  
  x.compare!
end
  