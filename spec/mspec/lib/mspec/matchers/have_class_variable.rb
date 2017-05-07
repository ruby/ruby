require 'mspec/matchers/variable'

class HaveClassVariableMatcher < VariableMatcher
  self.variables_method = :class_variables
  self.description      = 'class variable'
end

class Object
  def have_class_variable(variable)
    HaveClassVariableMatcher.new(variable)
  end
end