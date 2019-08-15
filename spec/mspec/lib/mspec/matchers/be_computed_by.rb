class BeComputedByMatcher
  def initialize(sym, *args)
    @method = sym
    @args = args
  end

  def matches?(array)
    array.each do |line|
      @receiver = line.shift
      @value = line.pop
      @arguments = line
      @arguments += @args
      @actual = @receiver.send(@method, *@arguments)
      return false unless @actual == @value
    end

    return true
  end

  def method_call
    method_call = "#{@receiver.inspect}.#{@method}"
    unless @arguments.empty?
      method_call = "#{method_call} from #{@arguments.map { |x| x.inspect }.join(", ")}"
    end
    method_call
  end

  def failure_message
    ["Expected #{@value.inspect}", "to be computed by #{method_call} (computed #{@actual.inspect} instead)"]
  end
end

module MSpecMatchers
  private def be_computed_by(sym, *args)
    BeComputedByMatcher.new(sym, *args)
  end
end
