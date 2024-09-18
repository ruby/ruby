# frozen_string_literal: true

module Lrama
  class Grammar
    class ParameterizingRule
      class Rule
        attr_reader :name, :parameters, :rhs_list, :required_parameters_count, :tag, :is_inline

        def initialize(name, parameters, rhs_list, tag: nil, is_inline: false)
          @name = name
          @parameters = parameters
          @rhs_list = rhs_list
          @tag = tag
          @is_inline = is_inline
          @required_parameters_count = parameters.count
        end

        def to_s
          "#{@name}(#{@parameters.map(&:s_value).join(', ')})"
        end
      end
    end
  end
end
