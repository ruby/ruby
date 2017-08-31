require 'mspec/matchers/variable'

class HaveInstanceVariableMatcher < VariableMatcher
  self.variables_method = :instance_variables
  self.description      = 'instance variable'
end

module MSpecMatchers
  private def have_instance_variable(variable)
    HaveInstanceVariableMatcher.new(variable)
  end
end
