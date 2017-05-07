require 'mspec/runner/formatters/spinner'
require 'yaml'

class MultiFormatter < SpinnerFormatter
  def initialize(out=nil)
    super(out)
    @counter = @tally = Tally.new
    @timer = TimerAction.new
    @timer.start
  end

  def aggregate_results(files)
    @timer.finish
    @exceptions = []

    files.each do |file|
      d = File.open(file, "r") { |f| YAML.load f }
      File.delete file

      @exceptions += Array(d['exceptions'])
      @tally.files!        d['files']
      @tally.examples!     d['examples']
      @tally.expectations! d['expectations']
      @tally.errors!       d['errors']
      @tally.failures!     d['failures']
    end
  end

  def print_exception(exc, count)
    print "\n#{count})\n#{exc}\n"
  end

  def finish
    super(false)
  end
end
