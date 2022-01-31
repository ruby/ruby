require 'mspec/runner/formatters/base'

class StderrSummaryFormatter < BaseFormatter
  def initialize(*args)
    super
    @result_out = $stderr
  end
end
