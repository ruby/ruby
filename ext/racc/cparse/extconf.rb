# frozen_string_literal: false
#

require 'mkmf'

have_func('rb_block_call')
have_func('rb_ary_subseq')

create_makefile 'racc/cparse'
