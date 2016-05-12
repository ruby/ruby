# frozen_string_literal: false
require 'mkmf'

$defs << "-DJSON_GENERATOR"
create_makefile 'json/ext/generator'
