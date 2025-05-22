# frozen_string_literal: true
require_relative 'helper'

class RDocGeneratorPOTTest < RDoc::TestCase

  def setup
    super

    @options = RDoc::Options.new
    @tmpdir = File.join Dir.tmpdir, "test_rdoc_generator_pot_#{$$}"
    FileUtils.mkdir_p @tmpdir

    @generator = RDoc::Generator::POT.new @store, @options

    @top_level = @store.add_file 'file.rb'
    @klass = @top_level.add_class RDoc::NormalClass, 'Object'
    @klass.add_comment 'This is a class', @top_level
    @klass.add_section 'This is a section', comment('This is a section comment')

    @const = RDoc::Constant.new "CONSTANT", "29", "This is a constant"

    @meth = RDoc::AnyMethod.new nil, 'method'
    @meth.record_location @top_level
    @meth.comment = 'This is a method'

    @attr = RDoc::Attr.new nil, 'attr', 'RW', ''
    @attr.record_location @top_level
    @attr.comment = 'This is an attribute'

    @klass.add_constant @const
    @klass.add_method @meth
    @klass.add_attribute @attr

    Dir.chdir @tmpdir
  end

  def teardown
    super

    Dir.chdir @pwd
    FileUtils.rm_rf @tmpdir
  end

  def test_generate
    @generator.generate

    assert_equal <<-POT, File.read(File.join(@tmpdir, 'rdoc.pot'))
# SOME DESCRIPTIVE TITLE.
# Copyright (C) YEAR THE PACKAGE'S COPYRIGHT HOLDER
# This file is distributed under the same license as the PACKAGE package.
# FIRST AUTHOR <EMAIL@ADDRESS>, YEAR.
#, fuzzy
msgid ""
msgstr ""
"Project-Id-Version: PACKAGE VERSEION\\n"
"Report-Msgid-Bugs-To:\\n"
"PO-Revision-Date: YEAR-MO_DA HO:MI+ZONE\\n"
"Last-Translator: FULL NAME <EMAIL@ADDRESS>\\n"
"Language-Team: LANGUAGE <LL@li.org>\\n"
"Language:\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=CHARSET\\n"
"Content-Transfer-Encoding: 8bit\\n"
"Plural-Forms: nplurals=INTEGER; plural=EXPRESSION;\\n"

#. Object
msgid "This is a class"
msgstr ""

#. Object::CONSTANT
msgid "This is a constant"
msgstr ""

#. Object#method
msgid "This is a method"
msgstr ""

#. Object: section title
msgid "This is a section"
msgstr ""

#. Object: This is a section
msgid "This is a section comment"
msgstr ""

#. Object#attr
msgid "This is an attribute"
msgstr ""
    POT
  end

end
