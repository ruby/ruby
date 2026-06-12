# frozen_string_literal: true

module Bundler
  module Plugin
    # Stands in for a source handled by a plugin that is not loaded yet, so
    # that the lockfile can still be parsed during the plugin install pass,
    # and by external tools reading a lockfile without the plugin installed.
    class UnloadedSource
      include API::Source

      # Unlike real plugin sources, where the handling class encodes the
      # source type, all unloaded sources share this class, so the type must
      # be compared explicitly.
      def ==(other)
        super && options["type"] == other.options["type"]
      end

      alias_method :eql?, :==

      def hash
        [super, options["type"]].hash
      end
    end
  end
end
