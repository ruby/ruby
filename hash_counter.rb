#!/usr/bin/ruby

class CountedHashable
  attr_reader :hash_calls, :eql_calls
  
  def initialize(value)
    @value = value
    @hash_calls = 0
    @eql_calls = 0
  end
  
  def hash
    @hash_calls += 1
    super
  end
  
  def eql?
    @eql_calls += 1
    super
  end
  
  def to_s
    "<CH #{@value.inspect}, hashes: #{@hash_calls}, eqles: #{@eql_calls}>"
  end
end

objects = [1, 2, 3].map { CountedHashable.new(_1) }

set = Set[123]

if set.fast_add?(objects.first)
  puts "fast_add? - added, hashed #{objects.first.hash_calls} times"
end

puts set

if set.add?(objects.last)
  puts "add? - added, hashed #{objects.last.hash_calls} times"
end

puts set
  