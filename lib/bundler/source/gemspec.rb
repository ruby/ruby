# frozen_string_literal: true

module Bundler
  class Source
    class Gemspec < Path
      attr_reader :gemspec

      def initialize(options)
        super
        @gemspec = options["gemspec"]
      end
    end
  end
end
