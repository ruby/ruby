require 'mspec/matchers/variable'

class HaveClassVariableMatcher < VariableMatcher
  self.variables_method = :class_variables
  self.description      = 'class variable'
end

module MSpecMatchers
  private def have_class_variable(variable)
    MSpec.deprecate __method__, '.should.class_variable_defined?'
    HaveClassVariableMatcher.new(variable)
  end
end
