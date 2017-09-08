# frozen_string_literal: true
# Psych could be a gem, so try to ask for it
begin
  gem "psych"
rescue LoadError
end if defined?(gem)

# Psych could be in the stdlib
# but it's too late if Syck is already loaded
begin
  require "psych" unless defined?(Syck)
rescue LoadError
  # Apparently Psych wasn't available. Oh well.
end

# At least load the YAML stdlib, whatever that may be
require "yaml" unless defined?(YAML.dump)

module Bundler
  # On encountering invalid YAML,
  # Psych raises Psych::SyntaxError
  if defined?(::Psych::SyntaxError)
    YamlLibrarySyntaxError = ::Psych::SyntaxError
  else # Syck raises ArgumentError
    YamlLibrarySyntaxError = ::ArgumentError
  end
end
