begin
  has_tk = compiled?('tk')
rescue NoMethodError
  # Probably, called manually (NOT from 'extmk.rb'). Force to make Makefile.
  has_tk = true
end

if has_tk
  require 'mkmf'
  create_makefile('tkutil')
end
