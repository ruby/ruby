module FormatterOverrides
  def example_pending(_); end
  def dump_pending(_); end
end

RSpec::Core::Formatters::ProgressFormatter.prepend FormatterOverrides
