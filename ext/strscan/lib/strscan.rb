# frozen_string_literal: true

case RUBY_ENGINE
when 'ruby'
  require 'strscan.so'
  require_relative 'strscan/strscan'
when 'jruby'
  require 'strscan.jar'
  JRuby::Util.load_ext('org.jruby.ext.strscan.StringScannerLibrary')
  require_relative 'strscan/strscan'
when 'truffleruby'
  if RUBY_ENGINE_VERSION.to_i >= 34
    require 'strscan/truffleruby'
  else
    $LOAD_PATH.delete __dir__
    require 'strscan'
  end
else
  raise NotImplementedError, "Unknown Ruby: #{RUBY_ENGINE}"
end
