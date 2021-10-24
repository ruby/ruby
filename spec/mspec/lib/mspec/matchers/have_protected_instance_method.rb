require 'mspec/matchers/method'

class HaveProtectedInstanceMethodMatcher < MethodMatcher
  def matches?(mod)
    @mod = mod
    mod.protected_instance_methods(@include_super).include? @method
  end

  def failure_message
    ["Expected #{@mod} to have protected instance method '#{@method.to_s}'",
     "but it does not"]
  end

  def negative_failure_message
    ["Expected #{@mod} NOT to have protected instance method '#{@method.to_s}'",
     "but it does"]
  end
end

module MSpecMatchers
  private def have_protected_instance_method(method, include_super = true)
    HaveProtectedInstanceMethodMatcher.new method, include_super
  end
end
