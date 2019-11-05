module MultiFormatter
  def self.extend_object(obj)
    super
    obj.multi_initialize
  end

  def multi_initialize
    @counter = @tally = Tally.new
    @timer = TimerAction.new
    @timer.start
  end

  def register
    super

    MSpec.register :start, self
    MSpec.register :unload, self
    MSpec.unregister :before, self
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
end
