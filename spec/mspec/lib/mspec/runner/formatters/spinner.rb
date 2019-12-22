require 'mspec/runner/formatters/base'

class SpinnerFormatter < BaseFormatter
  attr_reader :length

  Spins = %w!| / - \\!
  HOUR = 3600
  MIN = 60

  def initialize(out = nil)
    super(nil)

    @which = 0
    @loaded = 0
    self.length = 40
    @percent = 0
    @start = Time.now

    term = ENV['TERM']
    @color = (term != "dumb")
    @fail_color  = "32"
    @error_color = "32"
  end

  def register
    super

    MSpec.register :start, self
    MSpec.register :unload, self
  end

  def length=(length)
    @length = length
    @ratio = 100.0 / length
    @position = length / 2 - 2
  end

  def compute_etr
    return @etr = "00:00:00" if @percent == 0
    elapsed = Time.now - @start
    remain = (100 * elapsed / @percent) - elapsed

    hour = remain >= HOUR ? (remain / HOUR).to_i : 0
    remain -= hour * HOUR
    min = remain >= MIN ? (remain / MIN).to_i : 0
    sec = remain - min * MIN

    @etr = "%02d:%02d:%02d" % [hour, min, sec]
  end

  def compute_percentage
    @percent = @loaded * 100 / @total
    bar = ("=" * (@percent / @ratio)).ljust @length
    label = "%d%%" % @percent
    bar[@position, label.size] = label
    @bar = bar
  end

  def compute_progress
    compute_percentage
    compute_etr
  end

  def progress_line
    @which = (@which + 1) % Spins.size
    data = [Spins[@which], @bar, @etr, @counter.failures, @counter.errors]
    if @color
      "\r[%s | %s | %s] \e[0;#{@fail_color}m%6dF \e[0;#{@error_color}m%6dE\e[0m " % data
    else
      "\r[%s | %s | %s] %6dF %6dE " % data
    end
  end

  def clear_progress_line
    print "\r#{' '*progress_line.length}"
  end

  # Callback for the MSpec :start event. Stores the total
  # number of files that will be processed.
  def start
    @total = MSpec.retrieve(:files).size
    compute_progress
    print progress_line
  end

  # Callback for the MSpec :unload event. Increments the number
  # of files that have been run.
  def unload
    @loaded += 1
    compute_progress
    print progress_line
  end

  # Callback for the MSpec :exception event. Changes the color
  # used to display the tally of errors and failures
  def exception(exception)
    super
    @fail_color =  "31" if exception.failure?
    @error_color = "33" unless exception.failure?

    clear_progress_line
    print_exception(exception, @count)
    exceptions.clear
  end

  # Callback for the MSpec :after event. Updates the spinner.
  def after(state = nil)
    super(state)
    print progress_line
  end
end
