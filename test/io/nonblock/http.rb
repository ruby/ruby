
require 'benchmark'

TOPICS = ["cats", "dogs", "pigs", "skeletons"]

require 'net/http'
require 'uri'
require_relative 'scheduler'

def fetch_topics(topics, blocking: true)
	responses = {}
	
	conditions = topics.map do |topic|
		condition = Scheduler::Condition.new
		
		Fiber.new(blocking: blocking) do
			puts "Fetching #{topic} (#{Thread.current.blocking?})"
			
			uri = URI("https://www.google.com/search?q=#{topic}")
			responses[topic] = Net::HTTP.get(uri).scan(topic).size
			
			puts "Finished fetching #{topic}"
			
			condition.signal
		end.resume
		
		condition
	end
	
	# Wait for all requests to finish:
	conditions.each(&:wait)
	
	return responses
end

Benchmark.benchmark do |benchmark|
	benchmark.report("blocking") do
		puts
		
		Thread.new do
			scheduler = Scheduler.new
			Thread.current.scheduler = scheduler
			
			Fiber.new(blocking: true) do
				pp fetch_topics(TOPICS, blocking: true)
			end.resume
			
			scheduler.run
		end.join
	end
	
	benchmark.report("nonblocking") do
		puts
		
		Thread.new do
			scheduler = Scheduler.new
			Thread.current.scheduler = scheduler
			
			Fiber.new(blocking: false) do
				pp fetch_topics(TOPICS, blocking: false)
			end.resume
			
			scheduler.run
		end
	end
end
