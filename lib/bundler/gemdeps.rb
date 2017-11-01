# frozen_string_literal: true

module Bundler
  class Gemdeps
    def initialize(runtime)
      @runtime = runtime
    end

    def requested_specs
      @runtime.requested_specs
    end

    def specs
      @runtime.specs
    end

    def dependencies
      @runtime.dependencies
    end

    def current_dependencies
      @runtime.current_dependencies
    end

    def requires
      @runtime.requires
    end
  end
end
