require 'mkmf'

base_fig = 0
src = "(BASE * (BASE+1)) / BASE == (BASE+1)"
while try_static_assert(src, nil, "-DBASE=10#{'0'*base_fig}UL")
  base_fig += 1
end
$defs << "-DBASE=1#{'0'*base_fig}UL" << "-DBASE_FIG=#{base_fig}"

create_makefile('bigdecimal')
