module Lrama
  class Grammar
    class ParameterizingRule
      class Rule
        attr_reader :name, :parameters, :rhs_list, :required_parameters_count

        def initialize(name, parameters, rhs_list)
          @name = name
          @parameters = parameters
          @rhs_list = rhs_list
          @required_parameters_count = parameters.count
        end
      end
    end
  end
end
