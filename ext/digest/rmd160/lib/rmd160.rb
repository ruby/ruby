# frozen_string_literal: false

require 'digest'

if RUBY_ENGINE == 'jruby'
  JRuby::Util.load_ext("org.jruby.ext.digest.RMD160")
else
  require 'digest/rmd160.so'
end
