# frozen_string_literal: true
# This exists just to satisfy bugs in marshal'd gemspecs that
# contain a reference to YAML::PrivateType. We prune these out
# in Specification._load, but if we don't have the constant, Marshal
# blows up.

module Psych # :nodoc:
  class PrivateType # :nodoc:
  end
end
