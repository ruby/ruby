require "benchmark/ips"
require "json"
require "oj"
require "rapidjson"

if ENV["ONLY"]
  RUN = ENV["ONLY"].split(/[,: ]/).map{|x| [x.to_sym, true] }.to_h
  RUN.default = false
elsif ENV["EXCEPT"]
  RUN = ENV["EXCEPT"].split(/[,: ]/).map{|x| [x.to_sym, false] }.to_h
  RUN.default = true
else
  RUN = Hash.new(true)
end

def benchmark_parsing(name, json_output)
  puts "== Parsing #{name} (#{json_output.size} bytes)"

  Benchmark.ips do |x|
    x.report("json")      { JSON.parse(json_output) } if RUN[:json]
    x.report("oj")        { Oj.load(json_output) } if RUN[:oj]
    x.report("oj strict") { Oj.strict_load(json_output) } if RUN[:oj]
    x.report("Oj::Parser") { Oj::Parser.usual.parse(json_output) } if RUN[:oj]
    x.report("rapidjson") { RapidJSON.parse(json_output) } if RUN[:rapidjson]
    x.compare!(order: :baseline)
  end
  puts
end

benchmark_parsing "small nested array", JSON.dump([[1,2,3,4,5]]*10)
benchmark_parsing "small hash", JSON.dump({ "username" => "jhawthorn", "id" => 123, "event" => "wrote json serializer" })

benchmark_parsing "test from oj", <<JSON
{"a":"Alpha","b":true,"c":12345,"d":[true,[false,[-123456789,null],3.9676,["Something else.",false],null]],"e":{"zero":null,"one":1,"two":2,"three":[3],"four":[0,1,2,3,4]},"f":null,"h":{"a":{"b":{"c":{"d":{"e":{"f":{"g":null}}}}}}},"i":[[[[[[[null]]]]]]]}
JSON

benchmark_parsing "twitter.json", File.read("#{__dir__}/data/twitter.json")
benchmark_parsing "citm_catalog.json", File.read("#{__dir__}/data/citm_catalog.json")
benchmark_parsing "canada.json", File.read("#{__dir__}/data/canada.json")
