# frozen_string_literal: true
require 'rubygems/source/specific_file'

unless Gem::Deprecate.skip
  Kernel.warn "#{Gem.location_of_caller(3).join(':')}: Warning: Requiring rubygems/source_specific_file is deprecated; please use rubygems/source/specific_file instead."
end
