# frozen_string_literal: true
require 'minitest_helper'

class TestRDocGeneratorPOTPO < RDoc::TestCase

  def setup
    super
    @po = RDoc::Generator::POT::PO.new
  end

  def test_empty
    assert_equal header, @po.to_s
  end

  def test_have_entry
    @po.add(entry("Hello", {}))
    assert_equal <<-PO, @po.to_s
#{header}
msgid "Hello"
msgstr ""
    PO
  end

  private

  def entry(msgid, options)
    RDoc::Generator::POT::POEntry.new(msgid, options)
  end

  def header
    <<-'HEADER'
# SOME DESCRIPTIVE TITLE.
# Copyright (C) YEAR THE PACKAGE'S COPYRIGHT HOLDER
# This file is distributed under the same license as the PACKAGE package.
# FIRST AUTHOR <EMAIL@ADDRESS>, YEAR.
#, fuzzy
msgid ""
msgstr ""
"Project-Id-Version: PACKAGE VERSEION\n"
"Report-Msgid-Bugs-To:\n"
"PO-Revision-Date: YEAR-MO_DA HO:MI+ZONE\n"
"Last-Translator: FULL NAME <EMAIL@ADDRESS>\n"
"Language-Team: LANGUAGE <LL@li.org>\n"
"Language:\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=CHARSET\n"
"Content-Transfer-Encoding: 8bit\n"
"Plural-Forms: nplurals=INTEGER; plural=EXPRESSION;\n"
    HEADER
  end

end
