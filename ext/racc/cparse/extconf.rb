# frozen_string_literal: false
# $Id: a9187b5bc40e6adf05e7b6ee5b370b39a3429ecd $

require 'mkmf'

have_func('rb_ary_subseq')

create_makefile 'racc/cparse'
