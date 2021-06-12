# frozen_string_literal: false

require 'digest'

if RUBY_ENGINE == 'jruby'
  JRuby::Util.load_ext("org.jruby.ext.digest.MD5")
else
  require 'digest/md5.so'
end
