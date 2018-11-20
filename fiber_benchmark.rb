#!/usr/bin/env ruby

require 'fiber'
require 'benchmark'

class Ring
   attr_reader :id
   attr_accessor :attach 

   def initialize(id)
      @id = id
      #puts "Creating ring ... #{id}"
      @fiber = Fiber.new do
         pass_message
      end
   end

   def |(other)
      other.attach = self if !other.nil?
      #puts "attaching #{@id} to #{other.id}" if !other.nil?
      other
   end

   def resume
      @fiber.resume
    end

   def pass_message
      #puts "I'm fiber #{@id}"
      while message = message_in
         #puts "... #{@id} I received message #{message}"
         # do something with message
         message_out(message)      
      end
   end

   def message_in
      #puts "Resuming #{@attach.id}" if !@attach.nil?
      @attach.resume if !@attach.nil?
   end

   def message_out(message)
      Fiber.yield(message)
   end

end

class RingStart < Ring
   attr_accessor :message
   def initialize(n, m, message)
      @m = m
      @message = message
      super(n)
   end
   
   def pass_message 
      loop { message_out(@message) }
   end

end


def create_chain_r(i, chain)
   # recursive version
   return chain if i<=0
   r = chain.nil? ? Ring.new(i) :  chain | Ring.new(i)
   create_chain(i-1, r)
end

def create_chain(n, chain)
   # loop version
   # needed to avoid stack overflow for high n
   n.downto(0) {
      chain = chain | Ring.new(n)
   }
   chain
end

def run_benchmark(n, m)
  mess = :hello
  ringu = nil
  chain = nil

  tm = Benchmark.measure {
     ringu = RingStart.new(0, m, mess)
     chain = create_chain(n, ringu)
  }.format("%10.6r\n").gsub!(/\(|\)/, "")

  puts "setup time for #{n} fibers: #{tm}"

  tm  = Benchmark.measure {
     m.times { ringu.message = chain.resume }
  }.format("%10.6r\n").gsub!(/\(|\)/, "")

  puts "execution time for #{m} messages: #{tm}"
end

n = (ARGV[0] || 1000).to_i
m = (ARGV[1] || 10000).to_i

5.times do
  run_benchmark(n, m)
end
