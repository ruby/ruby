require 'mspec/runner/formatters/base'

class MethodFormatter < BaseFormatter
  attr_accessor :methods

  def initialize(out = nil)
    super(out)
    @methods = Hash.new do |h, k|
      hash = {}
      hash[:examples]     = 0
      hash[:expectations] = 0
      hash[:failures]     = 0
      hash[:errors]       = 0
      hash[:exceptions]   = []
      h[k] = hash
    end
  end

  # Returns the type of method as a "class", "instance",
  # or "unknown".
  def method_type(sep)
    case sep
    when '.', '::'
      "class"
    when '#'
      "instance"
    else
      "unknown"
    end
  end

  # Callback for the MSpec :before event. Parses the
  # describe string into class and method if possible.
  # Resets the tallies so the counts are only for this
  # example.
  def before(state)
    super(state)

    # The pattern for a method name is not correctly
    # restrictive but it is simplistic and useful
    # for our purpose.
    /^([A-Za-z_]+\w*)(\.|#|::)([^ ]+)/ =~ state.describe
    @key = $1 && $2 && $3 ? "#{$1}#{$2}#{$3}" : state.describe

    unless methods.key? @key
      h = methods[@key]
      h[:class]       = "#{$1}"
      h[:method]      = "#{$3}"
      h[:type]        = method_type $2
      h[:description] = state.description
    end

    tally.counter.examples     = 0
    tally.counter.expectations = 0
    tally.counter.failures     = 0
    tally.counter.errors       = 0

    @exceptions = []
  end

  # Callback for the MSpec :after event. Sets or adds to
  # tallies for the example block.
  def after(state = nil)
    super(state)

    h = methods[@key]
    h[:examples]     += tally.counter.examples
    h[:expectations] += tally.counter.expectations
    h[:failures]     += tally.counter.failures
    h[:errors]       += tally.counter.errors
    @exceptions.each do |exc|
      h[:exceptions] << "#{exc.message}\n#{exc.backtrace}\n"
    end
  end

  # Callback for the MSpec :finish event. Prints out the
  # summary information in YAML format for all the methods.
  def finish
    print "---\n"

    methods.each do |key, hash|
      print key.inspect, ":\n"
      print "  class: ",        hash[:class].inspect,        "\n"
      print "  method: ",       hash[:method].inspect,       "\n"
      print "  type: ",         hash[:type],                 "\n"
      print "  description: ",  hash[:description].inspect,  "\n"
      print "  examples: ",     hash[:examples],             "\n"
      print "  expectations: ", hash[:expectations],         "\n"
      print "  failures: ",     hash[:failures],             "\n"
      print "  errors: ",       hash[:errors],               "\n"
      print "  exceptions:\n"
      hash[:exceptions].each { |exc| print "  - ", exc.inspect, "\n" }
    end
  end
end
