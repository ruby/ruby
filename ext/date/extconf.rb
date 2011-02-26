require 'mkmf'
have_func('floorl', 'math.h')
have_func('roundl', 'math.h')
create_makefile('date_core')
