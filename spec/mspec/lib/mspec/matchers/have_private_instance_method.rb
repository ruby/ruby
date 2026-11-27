require 'mspec/matchers/method'

class HavePrivateInstanceMethodMatcher < MethodMatcher
  def matches?(mod)
    @mod = mod
    mod.private_instance_methods(@include_super).include? @method
  end

  def failure_message
    ["Expected #{@mod} to have private instance method '#{@method.to_s}'",
     "but it does not"]
  end

  def negative_failure_message
    ["Expected #{@mod} NOT to have private instance method '#{@method.to_s}'",
     "but it does"]
  end
end

module MSpecMatchers
  private def have_private_instance_method(method, include_super = true)
    MSpec.deprecate __method__, '.private_instance_methods(false).should.include?'
    HavePrivateInstanceMethodMatcher.new method, include_super
  end
end
