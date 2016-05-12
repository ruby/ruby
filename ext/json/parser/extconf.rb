# frozen_string_literal: false
require 'mkmf'

have_func("rb_enc_raise", "ruby.h")

create_makefile 'json/ext/parser'
