# encoding: utf-8
# frozen_string_literal: false

require 'minitest/unit'

class MiniTest::Unit # :nodoc:
  def run_benchmarks # :nodoc:
    _run_anything :benchmark
  end

  def benchmark_suite_header suite # :nodoc:
    "\n#{suite}\t#{suite.bench_range.join("\t")}"
  end

  class TestCase
    ##
    # Returns a set of ranges stepped exponentially from +min+ to
    # +max+ by powers of +base+. Eg:
    #
    #   bench_exp(2, 16, 2) # => [2, 4, 8, 16]

    def self.bench_exp min, max, base = 10
      min = (Math.log10(min) / Math.log10(base)).to_i
      max = (Math.log10(max) / Math.log10(base)).to_i

      (min..max).map { |m| base ** m }.to_a
    end

    ##
    # Returns a set of ranges stepped linearly from +min+ to +max+ by
    # +step+. Eg:
    #
    #   bench_linear(20, 40, 10) # => [20, 30, 40]

    def self.bench_linear min, max, step = 10
      (min..max).step(step).to_a
    rescue LocalJumpError # 1.8.6
      r = []; (min..max).step(step) { |n| r << n }; r
    end

    ##
    # Returns the benchmark methods (methods that start with bench_)
    # for that class.

    def self.benchmark_methods # :nodoc:
      public_instance_methods(true).grep(/^bench_/).map { |m| m.to_s }.sort
    end

    ##
    # Returns all test suites that have benchmark methods.

    def self.benchmark_suites
      TestCase.test_suites.reject { |s| s.benchmark_methods.empty? }
    end

    ##
    # Specifies the ranges used for benchmarking for that class.
    # Defaults to exponential growth from 1 to 10k by powers of 10.
    # Override if you need different ranges for your benchmarks.
    #
    # See also: ::bench_exp and ::bench_linear.

    def self.bench_range
      bench_exp 1, 10_000
    end

    ##
    # Runs the given +work+, gathering the times of each run. Range
    # and times are then passed to a given +validation+ proc. Outputs
    # the benchmark name and times in tab-separated format, making it
    # easy to paste into a spreadsheet for graphing or further
    # analysis.
    #
    # Ranges are specified by ::bench_range.
    #
    # Eg:
    #
    #   def bench_algorithm
    #     validation = proc { |x, y| ... }
    #     assert_performance validation do |n|
    #       @obj.algorithm(n)
    #     end
    #   end

    def assert_performance validation, &work
      range = self.class.bench_range

      io.print "#{__name__}"

      times = []

      range.each do |x|
        GC.start
        t0 = Time.now
        instance_exec(x, &work)
        t = Time.now - t0

        io.print "\t%9.6f" % t
        times << t
      end
      io.puts

      validation[range, times]
    end

    ##
    # Runs the given +work+ and asserts that the times gathered fit to
    # match a constant rate (eg, linear slope == 0) within a given
    # +threshold+. Note: because we're testing for a slope of 0, R^2
    # is not a good determining factor for the fit, so the threshold
    # is applied against the slope itself. As such, you probably want
    # to tighten it from the default.
    #
    # See http://www.graphpad.com/curvefit/goodness_of_fit.htm for
    # more details.
    #
    # Fit is calculated by #fit_linear.
    #
    # Ranges are specified by ::bench_range.
    #
    # Eg:
    #
    #   def bench_algorithm
    #     assert_performance_constant 0.9999 do |n|
    #       @obj.algorithm(n)
    #     end
    #   end

    def assert_performance_constant threshold = 0.99, &work
      validation = proc do |range, times|
        a, b, rr = fit_linear range, times
        assert_in_delta 0, b, 1 - threshold
        [a, b, rr]
      end

      assert_performance validation, &work
    end

    ##
    # Runs the given +work+ and asserts that the times gathered fit to
    # match a exponential curve within a given error +threshold+.
    #
    # Fit is calculated by #fit_exponential.
    #
    # Ranges are specified by ::bench_range.
    #
    # Eg:
    #
    #   def bench_algorithm
    #     assert_performance_exponential 0.9999 do |n|
    #       @obj.algorithm(n)
    #     end
    #   end

    def assert_performance_exponential threshold = 0.99, &work
      assert_performance validation_for_fit(:exponential, threshold), &work
    end

    ##
    # Runs the given +work+ and asserts that the times gathered fit to
    # match a logarithmic curve within a given error +threshold+.
    #
    # Fit is calculated by #fit_logarithmic.
    #
    # Ranges are specified by ::bench_range.
    #
    # Eg:
    #
    #   def bench_algorithm
    #     assert_performance_logarithmic 0.9999 do |n|
    #       @obj.algorithm(n)
    #     end
    #   end

    def assert_performance_logarithmic threshold = 0.99, &work
      assert_performance validation_for_fit(:logarithmic, threshold), &work
    end

    ##
    # Runs the given +work+ and asserts that the times gathered fit to
    # match a straight line within a given error +threshold+.
    #
    # Fit is calculated by #fit_linear.
    #
    # Ranges are specified by ::bench_range.
    #
    # Eg:
    #
    #   def bench_algorithm
    #     assert_performance_linear 0.9999 do |n|
    #       @obj.algorithm(n)
    #     end
    #   end

    def assert_performance_linear threshold = 0.99, &work
      assert_performance validation_for_fit(:linear, threshold), &work
    end

    ##
    # Runs the given +work+ and asserts that the times gathered curve
    # fit to match a power curve within a given error +threshold+.
    #
    # Fit is calculated by #fit_power.
    #
    # Ranges are specified by ::bench_range.
    #
    # Eg:
    #
    #   def bench_algorithm
    #     assert_performance_power 0.9999 do |x|
    #       @obj.algorithm
    #     end
    #   end

    def assert_performance_power threshold = 0.99, &work
      assert_performance validation_for_fit(:power, threshold), &work
    end

    ##
    # Takes an array of x/y pairs and calculates the general R^2 value.
    #
    # See: http://en.wikipedia.org/wiki/Coefficient_of_determination

    def fit_error xys
      y_bar  = sigma(xys) { |x, y| y } / xys.size.to_f
      ss_tot = sigma(xys) { |x, y| (y    - y_bar) ** 2 }
      ss_err = sigma(xys) { |x, y| (yield(x) - y) ** 2 }

      1 - (ss_err / ss_tot)
    end

    ##
    # To fit a functional form: y = ae^(bx).
    #
    # Takes x and y values and returns [a, b, r^2].
    #
    # See: http://mathworld.wolfram.com/LeastSquaresFittingExponential.html

    def fit_exponential xs, ys
      n     = xs.size
      xys   = xs.zip(ys)
      sxlny = sigma(xys) { |x,y| x * Math.log(y) }
      slny  = sigma(xys) { |x,y| Math.log(y)     }
      sx2   = sigma(xys) { |x,y| x * x           }
      sx    = sigma xs

      c = n * sx2 - sx ** 2
      a = (slny * sx2 - sx * sxlny) / c
      b = ( n * sxlny - sx * slny ) / c

      return Math.exp(a), b, fit_error(xys) { |x| Math.exp(a + b * x) }
    end

    ##
    # To fit a functional form: y = a + b*ln(x).
    #
    # Takes x and y values and returns [a, b, r^2].
    #
    # See: http://mathworld.wolfram.com/LeastSquaresFittingLogarithmic.html

    def fit_logarithmic xs, ys
      n     = xs.size
      xys   = xs.zip(ys)
      slnx2 = sigma(xys) { |x,y| Math.log(x) ** 2 }
      slnx  = sigma(xys) { |x,y| Math.log(x)      }
      sylnx = sigma(xys) { |x,y| y * Math.log(x)  }
      sy    = sigma(xys) { |x,y| y                }

      c = n * slnx2 - slnx ** 2
      b = ( n * sylnx - sy * slnx ) / c
      a = (sy - b * slnx) / n

      return a, b, fit_error(xys) { |x| a + b * Math.log(x) }
    end


    ##
    # Fits the functional form: a + bx.
    #
    # Takes x and y values and returns [a, b, r^2].
    #
    # See: http://mathworld.wolfram.com/LeastSquaresFitting.html

    def fit_linear xs, ys
      n   = xs.size
      xys = xs.zip(ys)
      sx  = sigma xs
      sy  = sigma ys
      sx2 = sigma(xs)  { |x|   x ** 2 }
      sxy = sigma(xys) { |x,y| x * y  }

      c = n * sx2 - sx**2
      a = (sy * sx2 - sx * sxy) / c
      b = ( n * sxy - sx * sy ) / c

      return a, b, fit_error(xys) { |x| a + b * x }
    end

    ##
    # To fit a functional form: y = ax^b.
    #
    # Takes x and y values and returns [a, b, r^2].
    #
    # See: http://mathworld.wolfram.com/LeastSquaresFittingPowerLaw.html

    def fit_power xs, ys
      n       = xs.size
      xys     = xs.zip(ys)
      slnxlny = sigma(xys) { |x, y| Math.log(x) * Math.log(y) }
      slnx    = sigma(xs)  { |x   | Math.log(x)               }
      slny    = sigma(ys)  { |   y| Math.log(y)               }
      slnx2   = sigma(xs)  { |x   | Math.log(x) ** 2          }

      b = (n * slnxlny - slnx * slny) / (n * slnx2 - slnx ** 2);
      a = (slny - b * slnx) / n

      return Math.exp(a), b, fit_error(xys) { |x| (Math.exp(a) * (x ** b)) }
    end

    ##
    # Enumerates over +enum+ mapping +block+ if given, returning the
    # sum of the result. Eg:
    #
    #   sigma([1, 2, 3])                # => 1 + 2 + 3 => 7
    #   sigma([1, 2, 3]) { |n| n ** 2 } # => 1 + 4 + 9 => 14

    def sigma enum, &block
      enum = enum.map(&block) if block
      enum.inject { |sum, n| sum + n }
    end

    ##
    # Returns a proc that calls the specified fit method and asserts
    # that the error is within a tolerable threshold.

    def validation_for_fit msg, threshold
      proc do |range, times|
        a, b, rr = send "fit_#{msg}", range, times
        assert_operator rr, :>=, threshold
        [a, b, rr]
      end
    end
  end
end

class MiniTest::Spec
  ##
  # This is used to define a new benchmark method. You usually don't
  # use this directly and is intended for those needing to write new
  # performance curve fits (eg: you need a specific polynomial fit).
  #
  # See ::bench_performance_linear for an example of how to use this.

  def self.bench name, &block
    define_method "bench_#{name.gsub(/\W+/, '_')}", &block
  end

  ##
  # Specifies the ranges used for benchmarking for that class.
  #
  #   bench_range do
  #     bench_exp(2, 16, 2)
  #   end
  #
  # See Unit::TestCase.bench_range for more details.

  def self.bench_range &block
    return super unless block

    meta = (class << self; self; end)
    meta.send :define_method, "bench_range", &block
  end

  ##
  # Create a benchmark that verifies that the performance is linear.
  #
  #   describe "my class" do
  #     bench_performance_linear "fast_algorithm", 0.9999 do |n|
  #       @obj.fast_algorithm(n)
  #     end
  #   end

  def self.bench_performance_linear name, threshold = 0.99, &work
    bench name do
      assert_performance_linear threshold, &work
    end
  end

  ##
  # Create a benchmark that verifies that the performance is constant.
  #
  #   describe "my class" do
  #     bench_performance_constant "zoom_algorithm!" do |n|
  #       @obj.zoom_algorithm!(n)
  #     end
  #   end

  def self.bench_performance_constant name, threshold = 0.99, &work
    bench name do
      assert_performance_constant threshold, &work
    end
  end

  ##
  # Create a benchmark that verifies that the performance is exponential.
  #
  #   describe "my class" do
  #     bench_performance_exponential "algorithm" do |n|
  #       @obj.algorithm(n)
  #     end
  #   end

  def self.bench_performance_exponential name, threshold = 0.99, &work
    bench name do
      assert_performance_exponential threshold, &work
    end
  end
end
