#! /your/favourite/path/to/ruby
# -*- mode: ruby; coding: utf-8; indent-tabs-mode: nil; ruby-indent-level: 2 -*-
# -*- frozen_string_literal: true; -*-
# -*- warn_indent: true; -*-
#
# Copyright (c) 2017 Urabe, Shyouhei.  All rights reserved.
#
# This file is  a part of the programming language  Ruby.  Permission is hereby
# granted, to  either redistribute and/or  modify this file, provided  that the
# conditions  mentioned in  the file  COPYING are  met.  Consult  the file  for
# details.

require 'optparse'
require_relative '../controllers/application_controller.rb'

module RubyVM::Insns2VM
  def self.router argv
    options = { destdir: nil }
    targets = generate_parser(options).parse argv
    return targets.map do |i|
      next ApplicationController.new.generate i, options[:destdir]
    end
  end

  def self.generate_parser(options)
    OptionParser.new do |this|
      this.on "-I", "--srcdir=DIR", <<-'end'
        Historically this option has been passed to the script.  This is
        supposedly because at the beginning the script was placed
        outside of the ruby source tree.  Decades passed since the merge
        of YARV, now I can safely assume this feature is obsolescent.
        Just ignore the passed value here.
      end

      this.on "-L", "--vpath=SPEC", <<-'end'
        Likewise, this option is no longer supported.
      end

      this.on "--path-separator=SEP", /\A(?:\W\z|\.(\W).+)/, <<-'end'
        Old script says this option is a "separator for vpath".  I am
        confident we no longer need this option.
      end

      this.on "-Dname", "--enable=name[,name...]", Array, <<-'end'
        This option was used to override VM option that is defined in
        vm_opts.h. Now it is officially unsupported because vm_opts.h to
        remain mismatched with this option must break things.  Just edit
        vm_opts.h directly.
      end

      this.on "-Uname", "--disable=name[,name...]", Array, <<-'end'
        This option was used to override VM option that is defined in
        vm_opts.h. Now it is officially unsupported because vm_opts.h to
        remain mismatched with this option must break things.  Just edit
        vm_opts.h directly.
      end

      this.on "-i", "--insnsdef=FILE", "--instructions-def", <<-'end'
        This option was used to specify alternative path to insns.def.  For
        the same reason to ignore -I, we no longer support this.
      end

      this.on "-o", "--opt-operanddef=FILE", "--opt-operand-def", <<-'end'
        This option was used to specify alternative path to opt_operand.def.
        For the same reason to ignore -I, we no longer support this.
      end

      this.on "-u", "--opt-insnunifdef=FILE", "--opt-insn-unif-def", <<-'end'
        This option was used to specify alternative path to
        opt_insn_unif.def.  For the same reason to ignore -I, we no
        longer support this.
      end

      this.on "-C", "--[no-]use-const", <<-'end'
        We use const whenever possible now so this option is ignored.
        The author believes that C compilers can constant-fold.
      end

      this.on "-d", "--destdir", "--output-directory=DIR", <<-'begin' do |dir|
        THIS IS THE ONLY OPTION THAT WORKS today.  Change destination
        directory from the current working directory to the given path.
      begin
        raise "directory was not found in '#{dir}'" unless Dir.exist?(dir)
        options[:destdir] = dir
      end

      this.on "-V", "--[no-]verbose", <<-'end'
        Please let us ignore this and be modest.
      end
    end
  end
  private_class_method :generate_parser
end
