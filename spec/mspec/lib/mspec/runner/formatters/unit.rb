require 'mspec/expectations/expectations'
require 'mspec/runner/formatters/dotted'

class UnitdiffFormatter < DottedFormatter
  def finish
    print "\n\n#{@timer.format}\n"
    count = 0
    @exceptions.each do |exc|
      outcome = exc.failure? ? "FAILED" : "ERROR"
      print "\n#{count += 1})\n#{exc.description} #{outcome}\n"
      print exc.message, ":\n"
      print exc.backtrace, "\n"
    end
    print "\n#{@tally.format}\n"
  end

  def backtrace(exc)
    exc.backtrace && exc.backtrace.join("\n")
  end
  private :backtrace
end
