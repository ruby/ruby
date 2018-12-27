#! /your/favourite/path/to/ruby
# -*- Ruby -*-
# -*- frozen_string_literal: true; -*-
# -*- warn_indent: true; -*-
#
# Copyright (c) 2017 Urabe, Shyouhei.  All rights reserved.
#
# This file is  a part of the programming language  Ruby.  Permission is hereby
# granted, to  either redistribute and/or  modify this file, provided  that the
# conditions  mentioned in  the file  COPYING are  met.  Consult  the file  for
# details.

require_relative '../helpers/dumper'
require_relative '../models/instructions'
require_relative '../models/typemap'
require_relative '../loaders/vm_opts_h'

class ApplicationController
  def generate i, destdir
    path = Pathname.new i
    dst = destdir ? Pathname.new(destdir).join(i) : Pathname.new(i)
    dumper = RubyVM::Dumper.new dst
    return [path, dumper]
  end
end
