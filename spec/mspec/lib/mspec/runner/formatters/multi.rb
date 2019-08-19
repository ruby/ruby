require 'mspec/runner/formatters/spinner'

class MultiFormatter < SpinnerFormatter
  def initialize(out=nil)
    super(out)
    @counter = @tally = Tally.new
    @timer = TimerAction.new
    @timer.start
  end

  def aggregate_results(files)
    require 'yaml'

    @timer.finish
    @exceptions = []

    files.each do |file|
      contents = File.read(file)
      d = YAML.load(contents)
      File.delete file

      if d # The file might be empty if the child process died
        @exceptions += Array(d['exceptions'])
        @tally.files!        d['files']
        @tally.examples!     d['examples']
        @tally.expectations! d['expectations']
        @tally.errors!       d['errors']
        @tally.failures!     d['failures']
      end
    end
  end

  def print_exception(exc, count)
    print "\n#{count})\n#{exc}\n"
  end

  def finish
    super(false)
  end
end
