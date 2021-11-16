# frozen_string_literal: false
# -*- ruby -*-

require 'shellwords'
require 'rubygems/optparse/lib/optparse'

Gem::OptionParser.accept(Shellwords) {|s,| Shellwords.shellwords(s)}
