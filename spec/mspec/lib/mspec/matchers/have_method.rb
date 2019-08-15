require 'mspec/matchers/method'

class HaveMethodMatcher < MethodMatcher
  def matches?(mod)
    @mod = mod
    @mod.methods(@include_super).include? @method
  end

  def failure_message
    ["Expected #{@mod} to have method '#{@method.to_s}'",
     "but it does not"]
  end

  def negative_failure_message
    ["Expected #{@mod} NOT to have method '#{@method.to_s}'",
     "but it does"]
  end
end

module MSpecMatchers
  private def have_method(method, include_super=true)
    HaveMethodMatcher.new method, include_super
  end
end
