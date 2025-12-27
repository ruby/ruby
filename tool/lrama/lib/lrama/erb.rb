# rbs_inline: enabled
# frozen_string_literal: true

require "erb"

module Lrama
  class ERB
    # @rbs (String file, **untyped kwargs) -> String
    def self.render(file, **kwargs)
      new(file).render(**kwargs)
    end

    # @rbs (String file) -> void
    def initialize(file)
      input = File.read(file)
      if ::ERB.instance_method(:initialize).parameters.last.first == :key
        @erb = ::ERB.new(input, trim_mode: '-')
      else
        @erb = ::ERB.new(input, nil, '-') # steep:ignore UnexpectedPositionalArgument
      end
      @erb.filename = file
    end

    # @rbs (**untyped kwargs) -> String
    def render(**kwargs)
      @erb.result_with_hash(kwargs)
    end
  end
end
