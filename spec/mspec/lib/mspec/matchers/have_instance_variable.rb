require 'mspec/matchers/variable'

class HaveInstanceVariableMatcher < VariableMatcher
  self.variables_method = :instance_variables
  self.description      = 'instance variable'
end

module MSpecMatchers
  private def have_instance_variable(variable)
    MSpec.deprecate __method__, '.should.instance_variable_defined?'
    HaveInstanceVariableMatcher.new(variable)
  end
end
