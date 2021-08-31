require 'mspec/runner/formatters/dotted'

class DescribeFormatter < DottedFormatter
  # Callback for the MSpec :finish event. Prints a summary of
  # the number of errors and failures for each +describe+ block.
  def finish
    describes = Hash.new { |h,k| h[k] = Tally.new }

    @exceptions.each do |exc|
      desc = describes[exc.describe]
      exc.failure? ? desc.failures! : desc.errors!
    end

    print "\n"
    describes.each do |d, t|
      text = d.size > 40 ? "#{d[0,37]}..." : d.ljust(40)
      print "\n#{text} #{t.failure}, #{t.error}"
    end
    print "\n" unless describes.empty?

    print "\n#{@timer.format}\n\n#{@tally.format}\n"
  end
end
