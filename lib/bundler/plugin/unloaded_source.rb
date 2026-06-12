# frozen_string_literal: true

module Bundler
  module Plugin
    # Stands in for a source handled by a plugin that is not loaded yet, so
    # that the lockfile can still be parsed during the plugin install pass.
    class UnloadedSource
      include API::Source
    end
  end
end
