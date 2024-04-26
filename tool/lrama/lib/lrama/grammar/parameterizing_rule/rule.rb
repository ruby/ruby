module Lrama
  class Grammar
    class ParameterizingRule
      class Rule
        attr_reader :name, :parameters, :rhs_list, :required_parameters_count, :is_inline

        def initialize(name, parameters, rhs_list, is_inline: false)
          @name = name
          @parameters = parameters
          @rhs_list = rhs_list
          @is_inline = is_inline
          @required_parameters_count = parameters.count
        end
      end
    end
  end
end
