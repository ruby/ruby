require 'benchmark_driver/output/simple'

# This replicates the legacy benchmark/driver.rb behavior.
class BenchmarkDriver::Output::Driver < BenchmarkDriver::Output::Simple
  def initialize(*)
    super
    @stdout = $stdout
    @strio  = StringIO.new
    $stdout = IOMultiplexer.new(@stdout, @strio)
  end

  def with_benchmark(*)
    super
  ensure
    logfile = "bmlog-#{Time.now.strftime('%Y%m%d-%H%M%S')}.#{$$}.log"
    puts "\nLog file: #{logfile}"

    $stdout = @stdout
    File.write(logfile, @strio.tap(&:rewind).read)
  end

  class IOMultiplexer
    def initialize(io1, io2)
      @io1 = io1
      @io2 = io2
    end

    [:write, :sync, :sync=, :puts, :print, :flush].each do |method|
      define_method(method) do |*args|
        @io1.send(method, *args)
        @io2.send(method, *args)
      end
    end
  end
  private_constant :IOMultiplexer
end
