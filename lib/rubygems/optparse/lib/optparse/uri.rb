# frozen_string_literal: false
# -*- ruby -*-

require 'rubygems/optparse/lib/optparse'
require 'uri'

Gem::OptionParser.accept(URI) {|s,| URI.parse(s) if s}
