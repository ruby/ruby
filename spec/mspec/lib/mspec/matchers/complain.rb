require 'mspec/helpers/io'

class ComplainMatcher
  def initialize(complaint = nil, options = nil)
    # the proper solution is to use double splat operator e.g.
    #   def initialize(complaint = nil, **options)
    # but we are trying to minimize language features required to run MSpec
    if complaint.is_a?(Hash)
      @complaint = nil
      @options = complaint
    else
      @complaint = complaint
      @options = options || {}
    end
  end

  def matches?(proc)
    @saved_err = $stderr
    @verbose = $VERBOSE
    begin
      err = $stderr = IOStub.new
      $VERBOSE = @options.key?(:verbose) ? @options[:verbose] : false
      Thread.current[:in_mspec_complain_matcher] = true
      proc.call
    ensure
      $VERBOSE = @verbose
      $stderr = @saved_err
      Thread.current[:in_mspec_complain_matcher] = false
    end

    @warning = err.to_s
    unless @complaint.nil?
      case @complaint
      when Regexp
        return false unless @warning =~ @complaint
      else
        return false unless @warning == @complaint
      end
    end

    return @warning.empty? ? false : true
  end

  def failure_message
    if @complaint.nil?
      ["Expected a warning", "but received none"]
    elsif @complaint.kind_of? Regexp
      ["Expected warning to match: #{@complaint.inspect}", "but got: #{@warning.chomp.inspect}"]
    else
      ["Expected warning: #{@complaint.inspect}", "but got: #{@warning.chomp.inspect}"]
    end
  end

  def negative_failure_message
    if @complaint.nil?
      ["Unexpected warning: ", @warning.chomp.inspect]
    elsif @complaint.kind_of? Regexp
      ["Expected warning not to match: #{@complaint.inspect}", "but got: #{@warning.chomp.inspect}"]
    else
      ["Expected warning: #{@complaint.inspect}", "but got: #{@warning.chomp.inspect}"]
    end
  end
end

module MSpecMatchers
  private def complain(complaint = nil, options = nil)
    ComplainMatcher.new(complaint, options)
  end
end
