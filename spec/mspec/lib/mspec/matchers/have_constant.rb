require 'mspec/matchers/variable'

class HaveConstantMatcher < VariableMatcher
  self.variables_method = :constants
  self.description      = 'constant'
end

class Object
  def have_constant(variable)
    HaveConstantMatcher.new(variable)
  end
end
