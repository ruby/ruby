# frozen_string_literal: true
##
# Raised when there is an error while building extensions.

require 'rubygems/exceptions'

class Gem::Ext::BuildError < Gem::InstallError
end
