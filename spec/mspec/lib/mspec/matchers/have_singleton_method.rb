require 'mspec/matchers/method'

class HaveSingletonMethodMatcher < MethodMatcher
  def matches?(obj)
    @obj = obj
    obj.singleton_methods(@include_super).include? @method
  end

  def failure_message
    ["Expected #{@obj} to have singleton method '#{@method.to_s}'",
     "but it does not"]
  end

  def negative_failure_message
    ["Expected #{@obj} NOT to have singleton method '#{@method.to_s}'",
     "but it does"]
  end
end

module MSpecMatchers
  private def have_singleton_method(method, include_super=true)
    HaveSingletonMethodMatcher.new method, include_super
  end
end
