# frozen_string_literal: false

require 'digest'

if RUBY_ENGINE == 'jruby'
  JRuby::Util.load_ext("org.jruby.ext.digest.SHA1")
else
  require 'digest/sha1.so'
end
