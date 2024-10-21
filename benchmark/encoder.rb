require "benchmark/ips"
require "json"
require "oj"

Oj.default_options = Oj.default_options.merge(mode: :compat)

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
  state = JSON::State.new(JSON.dump_default_options)
  {
    json_state: ["json (reuse)", proc { state.generate(ruby_obj) }],
    json: ["json", proc { JSON.dump(ruby_obj) }],
    oj: ["oj", proc { Oj.dump(ruby_obj) }],
  }
end

def benchmark_encoding(benchmark_name, ruby_obj, check_expected: true, except: [])
  json_output = JSON.dump(ruby_obj)
  puts "== Encoding #{benchmark_name} (#{json_output.bytesize} bytes)"

  impls = implementations(ruby_obj).select { |name| RUN[name] }
  except.each { |i| impls.delete(i) }

  Benchmark.ips do |x|
    expected = ::JSON.dump(ruby_obj) if check_expected
    impls.values.each do |name, block|
      begin
        result = block.call
        if check_expected && expected != result
          puts "#{name} does not match expected output. Skipping"
          puts "Expected:" + '-' * 40
          puts expected
          puts "Actual:" + '-' * 40
          puts result
          puts '-' * 40
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

# On the first two micro benchmarks, the limitting factor is that we have to create a Generator::State object for every
# call to `JSON.dump`, so we cause 2 allocations per call where alternatives only do one allocation.
# The performance difference is mostly more time spent in GC because of this extra pressure.
# If we re-use the same `JSON::State` instance, we're faster than Oj on the array benchmark, and much closer
# on the Hash one.
benchmark_encoding "small nested array", [[1,2,3,4,5]]*10
benchmark_encoding "small hash", { "username" => "jhawthorn", "id" => 123, "event" => "wrote json serializer" }

# On these benchmarks we perform well. Either on par or very closely faster/slower
benchmark_encoding "mixed utf8", ([("a" * 5000) + "€" + ("a" * 5000)] * 500), except: %i(json_state)
benchmark_encoding "mostly utf8", ([("€" * 3333)] * 500), except: %i(json_state)
benchmark_encoding "twitter.json", JSON.load_file("#{__dir__}/data/twitter.json"), except: %i(json_state)
benchmark_encoding "citm_catalog.json", JSON.load_file("#{__dir__}/data/citm_catalog.json"), except: %i(json_state)

# This benchmark spent the overwhelming majority of its time in `ruby_dtoa`. We rely on Ruby's implementation
# which uses a relatively old version of dtoa.c from David M. Gay.
# Oj in `compat` mode is ~10% slower than `json`, but in its default mode is noticeably faster here because
# it limits the precision of floats, breaking roundtriping.  That's not something we should emulate.
#
# Since a few years there are now much faster float to string implementations such as Ryu, Dragonbox, etc,
# but all these are implemented in C++11 or newer, making it hard if not impossible to include them.
# Short of a pure C99 implementation of these newer algorithms, there isn't much that can be done to match
# Oj speed without losing precision.
benchmark_encoding "canada.json", JSON.load_file("#{__dir__}/data/canada.json"), check_expected: false, except: %i(json_state)

benchmark_encoding "many #to_json calls", [{object: Object.new, int: 12, float: 54.3, class: Float, time: Time.now, date: Date.today}] * 20, except: %i(json_state)
