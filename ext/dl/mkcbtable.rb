# -*- ruby -*-

require 'mkmf'
$:.unshift File.dirname(__FILE__)
require 'type'
require 'dlconfig'

def mktable(rettype, fnum, argc)
  code =
    "rb_dl_callback_table[#{rettype}][#{fnum}] = &rb_dl_callback_func_#{rettype.to_s}_#{fnum};"
  return code
end

DLTYPE.keys.sort.each{|t|
  for n in 0..(MAX_CALLBACK - 1)
    print(mktable(t, n, 15), "\n")
  end
}
