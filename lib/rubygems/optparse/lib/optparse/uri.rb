# frozen_string_literal: false
# -*- ruby -*-

require_relative '../optparse'
require_relative '../../../vendor/uri/lib/uri'

Gem::OptionParser.accept(Gem::URI) {|s,| Gem::URI.parse(s) if s}
