require 'mspec/runner/formatters/base'

class StatsPerFileFormatter < BaseFormatter
  def initialize(out = nil)
    super(out)
    @data = {}
    @root = File.expand_path(MSpecScript.get(:prefix) || '.')
  end

  def register
    super
    MSpec.register :load, self
    MSpec.register :unload, self
  end

  # Resets the tallies so the counts are only for this file.
  def load
    tally.counter.examples = 0
    tally.counter.errors = 0
    tally.counter.failures = 0
    tally.counter.tagged = 0
  end

  def unload
    file = format_file MSpec.file

    raise if @data.key?(file)
    @data[file] = {
      examples: tally.counter.examples,
      errors: tally.counter.errors,
      failures: tally.counter.failures,
      tagged: tally.counter.tagged,
    }
  end

  def finish
    width = @data.keys.max_by(&:size).size
    f = "%3d"
    @data.each_pair do |file, data|
      total = data[:examples]
      passing = total - data[:errors] - data[:failures] - data[:tagged]
      puts "#{file.ljust(width)}  #{f % passing}/#{f % total}"
    end

    require 'yaml'
    yaml = YAML.dump(@data)
    File.write "results-#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}.yml", yaml
  end

  private def format_file(file)
    if file.start_with?(@root)
      file[@root.size+1..-1]
    else
      raise file
    end
  end
end
