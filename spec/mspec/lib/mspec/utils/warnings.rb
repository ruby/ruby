require 'mspec/guards/version'

# Always enable deprecation warnings when running MSpec, as ruby/spec tests for them,
# and like in most test frameworks, deprecation warnings should be enabled by default,
# so that deprecations are noticed before the breaking change.
# Disable experimental warnings, we want to test new experimental features in ruby/spec.
if Object.const_defined?(:Warning) and Warning.respond_to?(:[]=)
  Warning[:deprecated] = true
  Warning[:experimental] = false
end
