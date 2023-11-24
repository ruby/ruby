# frozen_string_literal: false
require 'mkmf'
if RUBY_ENGINE == 'ruby'
  create_makefile('stringio')
else
  File.write('Makefile', dummy_makefile("").join)
end
