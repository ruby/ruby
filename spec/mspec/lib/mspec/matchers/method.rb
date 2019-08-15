class MethodMatcher
  def initialize(method, include_super=true)
    @include_super = include_super
    @method = method.to_sym
  end

  def matches?(mod)
    raise Exception, "define #matches? in the subclass"
  end
end
