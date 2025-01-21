# frozen_string_literal: true

module Prism
  module Translation
    class Parser
      # A builder that knows how to convert more modern Ruby syntax
      # into whitequark/parser gem's syntax tree.
      class Builder < ::Parser::Builders::Default

      end
    end
  end
end
