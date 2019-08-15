require 'mspec/matchers/method'

class HaveInstanceMethodMatcher < MethodMatcher
  def matches?(mod)
    @mod = mod
    mod.instance_methods(@include_super).include? @method
  end

  def failure_message
    ["Expected #{@mod} to have instance method '#{@method.to_s}'",
     "but it does not"]
  end

  def negative_failure_message
    ["Expected #{@mod} NOT to have instance method '#{@method.to_s}'",
     "but it does"]
  end
end

module MSpecMatchers
  private def have_instance_method(method, include_super=true)
    HaveInstanceMethodMatcher.new method, include_super
  end
end
