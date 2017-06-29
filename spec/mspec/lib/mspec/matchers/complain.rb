require 'mspec/helpers/io'

class ComplainMatcher
  def initialize(complaint)
    @complaint = complaint
  end

  def matches?(proc)
    @saved_err = $stderr
    @stderr = $stderr = IOStub.new
    @verbose = $VERBOSE
    $VERBOSE = false

    proc.call

    unless @complaint.nil?
      case @complaint
      when Regexp
        return false unless $stderr =~ @complaint
      else
        return false unless $stderr == @complaint
      end
    end

    return $stderr.empty? ? false : true
  ensure
    $VERBOSE = @verbose
    $stderr = @saved_err
  end

  def failure_message
    if @complaint.nil?
      ["Expected a warning", "but received none"]
    elsif @complaint.kind_of? Regexp
      ["Expected warning to match: #{@complaint.inspect}", "but got: #{@stderr.chomp.inspect}"]
    else
      ["Expected warning: #{@complaint.inspect}", "but got: #{@stderr.chomp.inspect}"]
    end
  end

  def negative_failure_message
    if @complaint.nil?
      ["Unexpected warning: ", @stderr.chomp.inspect]
    elsif @complaint.kind_of? Regexp
      ["Expected warning not to match: #{@complaint.inspect}", "but got: #{@stderr.chomp.inspect}"]
    else
      ["Expected warning: #{@complaint.inspect}", "but got: #{@stderr.chomp.inspect}"]
    end
  end
end

module MSpecMatchers
  private def complain(complaint=nil)
    ComplainMatcher.new(complaint)
  end
end
