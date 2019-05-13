# $Id: 1e30abedf4eea155815d1efa5500ec817b10a2ab $

require 'mkmf'

have_func('rb_ary_subseq')

create_makefile 'racc/cparse'
