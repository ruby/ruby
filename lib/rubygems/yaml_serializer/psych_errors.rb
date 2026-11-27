# frozen_string_literal: true

unless defined?(Psych::VERSION)
  module Psych
    class Exception < ::RuntimeError; end
    class SyntaxError < Exception; end
    class DisallowedClass < Exception; end
    class BadAlias < Exception; end
    class AliasesNotEnabled < BadAlias; end
  end
end
