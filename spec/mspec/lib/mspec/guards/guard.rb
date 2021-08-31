require 'mspec/runner/mspec'
require 'mspec/runner/actions/tally'

class SpecGuard
  def self.report
    @report ||= Hash.new { |h,k| h[k] = [] }
  end

  def self.clear
    @report = nil
  end

  def self.finish
    report.keys.sort.each do |key|
      desc = report[key]
      size = desc.size
      spec = size == 1 ? "spec" : "specs"
      print "\n\n#{size} #{spec} omitted by guard: #{key}:\n"
      desc.each { |description| print "\n", description; }
    end

    print "\n\n"
  end

  def self.guards
    @guards ||= []
  end

  def self.clear_guards
    @guards = []
  end

  # Returns a partial Ruby version string based on +which+.
  # For example, if RUBY_VERSION = 8.2.3:
  #
  #  :major  => "8"
  #  :minor  => "8.2"
  #  :tiny   => "8.2.3"
  #  :teeny  => "8.2.3"
  #  :full   => "8.2.3"
  def self.ruby_version(which = :minor)
    case which
    when :major
      n = 1
    when :minor
      n = 2
    when :tiny, :teeny, :full
      n = 3
    end

    RUBY_VERSION.split('.')[0,n].join('.')
  end

  attr_accessor :name

  def initialize(*args)
    @parameters = args
  end

  def yield?(invert = false)
    return true if MSpec.mode? :unguarded

    allow = match? ^ invert

    if !allow and reporting?
      MSpec.guard
      MSpec.register :finish, SpecGuard
      MSpec.register :add,    self
      return true
    elsif MSpec.mode? :verify
      return true
    end

    allow
  end

  def run_if(name, &block)
    @name = name
    if block
      yield if yield?(false)
    else
      yield?(false)
    end
  ensure
    unregister
  end

  def run_unless(name, &block)
    @name = name
    if block
      yield if yield?(true)
    else
      yield?(true)
    end
  ensure
    unregister
  end

  def reporting?
    MSpec.mode?(:report) or
      (MSpec.mode?(:report_on) and SpecGuard.guards.include?(name))
  end

  def report_key
    "#{name} #{@parameters.join(", ")}"
  end

  def record(description)
    SpecGuard.report[report_key] << description
  end

  def add(example)
    record example.description
    MSpec.formatter.tally.counter.guards!
  end

  def unregister
    MSpec.unguard
    MSpec.unregister :add, self
  end

  def match?
    raise "must be implemented by the subclass"
  end
end

# Combined guards

def guard(condition, &block)
  raise "condition must be a Proc" unless condition.is_a?(Proc)
  raise LocalJumpError, "no block given" unless block
  return yield if MSpec.mode? :unguarded or MSpec.mode? :verify or MSpec.mode? :report
  yield if condition.call
end

def guard_not(condition, &block)
  raise "condition must be a Proc" unless condition.is_a?(Proc)
  raise LocalJumpError, "no block given" unless block
  return yield if MSpec.mode? :unguarded or MSpec.mode? :verify or MSpec.mode? :report
  yield unless condition.call
end
