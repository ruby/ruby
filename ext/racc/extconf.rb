# frozen_string_literal: false
# $Id$

require 'mkmf'

have_func('rb_ary_subseq')

create_makefile 'racc/cparse'
