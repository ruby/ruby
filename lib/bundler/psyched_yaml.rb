# frozen_string_literal: true

begin
  require "psych"
rescue LoadError
  # Apparently Psych wasn't available. Oh well.
end

# At least load the YAML stdlib, whatever that may be
require "yaml" unless defined?(YAML.dump)
