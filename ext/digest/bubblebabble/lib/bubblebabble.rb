# frozen_string_literal: false

require 'digest'

if RUBY_ENGINE == 'jruby'
  JRuby::Util.load_ext("org.jruby.ext.digest.BubbleBabble")
else
  require 'digest/bubblebabble.so'
end
