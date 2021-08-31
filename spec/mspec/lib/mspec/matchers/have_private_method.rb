require 'mspec/matchers/method'

class HavePrivateMethodMatcher < MethodMatcher
  def matches?(mod)
    @mod = mod
    mod.private_methods(@include_super).include? @method
  end

  def failure_message
    ["Expected #{@mod} to have private method '#{@method.to_s}'",
     "but it does not"]
  end

  def negative_failure_message
    ["Expected #{@mod} NOT to have private method '#{@method.to_s}'",
     "but it does"]
  end
end

module MSpecMatchers
  private def have_private_method(method, include_super = true)
    HavePrivateMethodMatcher.new method, include_super
  end
end
