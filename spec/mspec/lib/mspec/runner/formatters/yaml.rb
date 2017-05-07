require 'mspec/expectations/expectations'
require 'mspec/runner/formatters/dotted'

class YamlFormatter < DottedFormatter
  def initialize(out=nil)
    super(nil)

    if out.nil?
      @finish = $stdout
    else
      @finish = File.open out, "w"
    end
  end

  def switch
    @out = @finish
  end

  def after(state)
  end

  def finish
    switch

    print "---\n"
    print "exceptions:\n"
    @exceptions.each do |exc|
      outcome = exc.failure? ? "FAILED" : "ERROR"
      str =  "#{exc.description} #{outcome}\n"
      str << exc.message << "\n" << exc.backtrace
      print "- ", str.inspect, "\n"
    end

    print "time: ",         @timer.elapsed,              "\n"
    print "files: ",        @tally.counter.files,        "\n"
    print "examples: ",     @tally.counter.examples,     "\n"
    print "expectations: ", @tally.counter.expectations, "\n"
    print "failures: ",     @tally.counter.failures,     "\n"
    print "errors: ",       @tally.counter.errors,       "\n"
    print "tagged: ",       @tally.counter.tagged,       "\n"
  end
end
