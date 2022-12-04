
require 'benchmark'

TOPICS = ["cats", "dogs", "pigs", "skeletons", "zombies", "ocelots", "villagers", "pillagers"]

require 'net/http'
require 'uri'
require 'json'

require_relative 'scheduler'

def fetch_topics(topics)
  responses = {}

  topics.each do |topic|
    Fiber.new(blocking: Fiber.current.blocking?) do
      uri = URI("https://www.google.com/search?q=#{topic}")
      response = Net::HTTP.get(uri)
      responses[topic] = response.scan(topic).size
    end.resume
  end

  Fiber.scheduler&.run

  return responses
end

def sweep(repeats: 3, **options)
  times = (1..8).map do |i|
    $stderr.puts "Measuring #{i} topic(s) #{options.inspect}..."
    topics = TOPICS[0...i]

    Thread.new do
      Benchmark.realtime do
        scheduler = Scheduler.new
        Fiber.set_scheduler(scheduler)

        repeats.times do
          Fiber.new(**options) do
            pp fetch_topics(topics)
          end.resume

          scheduler.run
        end
      end
    end.value / repeats
  end

  puts options.inspect
  puts JSON.dump(times.map{|value| value.round(3)})
end

# sweep(blocking: true)
sweep(blocking: false)
