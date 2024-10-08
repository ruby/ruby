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

def implementations(ruby_obj)
  {
    json: ["json", proc { JSON.dump(ruby_obj) }],
    oj: ["oj", proc { Oj.dump(ruby_obj) }],
    rapidjson: ["rapidjson", proc { RapidJSON.dump(ruby_obj) }],
  }
end

def benchmark_encoding(benchmark_name, ruby_obj, check_expected: true)
  json_output = JSON.dump(ruby_obj)
  puts "== Encoding #{benchmark_name} (#{json_output.bytesize} bytes)"

  Benchmark.ips do |x|
    expected = ::JSON.dump(ruby_obj) if check_expected
    implementations(ruby_obj).select { |name| RUN[name] }.values.each do |name, block|
      begin
        result = block.call
        if check_expected && expected != result
          puts "#{name} does not match expected output. Skipping"
          next
        end
      rescue => error
        puts "#{name} unsupported (#{error})"
        next
      end
      x.report(name, &block)
    end
    x.compare!(order: :baseline)
  end
  puts
end

benchmark_encoding "small nested array", [[1,2,3,4,5]]*10
benchmark_encoding "small hash", { "username" => "jhawthorn", "id" => 123, "event" => "wrote json serializer" }
benchmark_encoding "twitter.json", JSON.load_file("#{__dir__}/data/twitter.json")
benchmark_encoding "citm_catalog.json", JSON.load_file("#{__dir__}/data/citm_catalog.json")
benchmark_encoding "canada.json", JSON.load_file("#{__dir__}/data/canada.json"), check_expected: false
benchmark_encoding "many #to_json calls", [{Object.new => Object.new, 12 => 54.3, Integer => Float, Time.now => Date.today}] * 20
