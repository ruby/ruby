require 'mspec/matchers/variable'

class HaveConstantMatcher < VariableMatcher
  self.variables_method = :constants
  self.description      = 'constant'
end

module MSpecMatchers
  private def have_constant(variable)
    MSpec.deprecate __method__, '.should.const_defined?'
    HaveConstantMatcher.new(variable)
  end
end
