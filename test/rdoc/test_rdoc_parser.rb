# -*- coding: us-ascii -*-
# frozen_string_literal: true

require_relative 'helper'

class TestRDocParser < RDoc::TestCase

  def setup
    super

    @RP = RDoc::Parser
    @binary_dat = File.expand_path '../binary.dat', __FILE__

    @fn = 'file.rb'
    @top_level = RDoc::TopLevel.new @fn
    @options = RDoc::Options.new
  end

  def test_class_binary_eh_ISO_2022_JP
    iso_2022_jp = File.join Dir.tmpdir, "test_rdoc_parser_#{$$}.rd"

    File.open iso_2022_jp, 'wb' do |io|
      io.write "# coding: ISO-2022-JP\n"
      io.write ":\e$B%3%^%s%I\e(B:\n"
    end

    refute @RP.binary? iso_2022_jp
  ensure
    File.unlink iso_2022_jp
  end

  def test_class_binary_eh_marshal
    marshal = File.join Dir.tmpdir, "test_rdoc_parser_#{$$}.marshal"
    File.open marshal, 'wb' do |io|
      io.write Marshal.dump('')
      io.write 'lots of text ' * 500
    end

    assert @RP.binary?(marshal)
  ensure
    File.unlink marshal
  end

  def test_class_binary_japanese_text
    file_name = File.expand_path '../test.ja.txt', __FILE__
    refute @RP.binary?(file_name)
  end

  def test_class_binary_large_japanese_rdoc
    capture_output do
      begin
        extenc, Encoding.default_external =
          Encoding.default_external, Encoding::US_ASCII
        file_name = File.expand_path '../test.ja.largedoc', __FILE__
        assert !@RP.binary?(file_name)
      ensure
        Encoding.default_external = extenc
      end
    end
  end

  def test_class_binary_japanese_rdoc
    file_name = File.expand_path '../test.ja.rdoc', __FILE__
    refute @RP.binary?(file_name)
  end

  def test_class_can_parse
    assert_equal @RP.can_parse(__FILE__), @RP::Ruby

    readme_file_name = File.expand_path '../test.txt', __FILE__

    assert_equal @RP::Simple, @RP.can_parse(readme_file_name)

    assert_equal @RP::Simple, @RP.can_parse(@binary_dat)

    jtest_file_name = File.expand_path '../test.ja.txt', __FILE__
    assert_equal @RP::Simple, @RP.can_parse(jtest_file_name)

    jtest_rdoc_file_name = File.expand_path '../test.ja.rdoc', __FILE__
    assert_equal @RP::Simple, @RP.can_parse(jtest_rdoc_file_name)

    readme_file_name = File.expand_path '../README', __FILE__
    assert_equal @RP::Simple, @RP.can_parse(readme_file_name)

    jtest_largerdoc_file_name = File.expand_path '../test.ja.largedoc', __FILE__
    assert_equal @RP::Simple, @RP.can_parse(jtest_largerdoc_file_name)

    @RP.alias_extension 'rdoc', 'largedoc'
    assert_equal @RP::Simple, @RP.can_parse(jtest_largerdoc_file_name)
  end

  def test_class_for_executable
    temp_dir do
      content = "#!/usr/bin/env ruby -w\n"
      File.open 'app', 'w' do |io| io.write content end
      app = @store.add_file 'app'

      parser = @RP.for app, 'app', content, @options, :stats

      assert_kind_of RDoc::Parser::Ruby, parser

      assert_equal 'app', parser.file_name
    end
  end

  def test_class_for_forbidden
    skip 'chmod not supported' if Gem.win_platform?

    tf = Tempfile.open 'forbidden' do |io|
      begin
        File.chmod 0000, io.path
        forbidden = @store.add_file io.path

        parser = @RP.for forbidden, 'forbidden', '', @options, :stats

        assert_nil parser
      ensure
        File.chmod 0400, io.path
      end
      io
    end
    tf.close!
  end

  def test_class_for_modeline
    temp_dir do
      content = "# -*- rdoc -*-\n= NEWS\n"

      File.open 'NEWS', 'w' do |io| io.write content end
      app = @store.add_file 'NEWS'

      parser = @RP.for app, 'NEWS', content, @options, :stats

      assert_kind_of RDoc::Parser::Simple, parser

      assert_equal "= NEWS\n", parser.content
    end
  end

  def test_can_parse_modeline
    readme_ext = File.join Dir.tmpdir, "README.EXT.#{$$}"

    File.open readme_ext, 'w' do |io|
      io.puts "# README.EXT -  -*- rdoc -*- created at: Mon Aug 7 16:45:54 JST 1995"
      io.puts
      io.puts "This document explains how to make extension libraries for Ruby."
    end

    assert_equal RDoc::Parser::Simple, @RP.can_parse(readme_ext)
  ensure
    File.unlink readme_ext
  end

  ##
  # Selenium hides a .jar file using a .txt extension.

  def test_class_can_parse_zip
    hidden_zip = File.expand_path '../hidden.zip.txt', __FILE__
    assert_nil @RP.can_parse(hidden_zip)
  end

  def test_check_modeline
    readme_ext = File.join Dir.tmpdir, "README.EXT.#{$$}"

    File.open readme_ext, 'w' do |io|
      io.puts "# README.EXT -  -*- RDoc -*- created at: Mon Aug 7 16:45:54 JST 1995"
      io.puts
      io.puts "This document explains how to make extension libraries for Ruby."
    end

    assert_equal 'rdoc', @RP.check_modeline(readme_ext)
  ensure
    File.unlink readme_ext
  end

  def test_check_modeline_coding
    readme_ext = File.join Dir.tmpdir, "README.EXT.#{$$}"

    File.open readme_ext, 'w' do |io|
      io.puts "# -*- coding: utf-8 -*-"
    end

    assert_nil @RP.check_modeline readme_ext
  ensure
    File.unlink readme_ext
  end

  def test_check_modeline_with_other
    readme_ext = File.join Dir.tmpdir, "README.EXT.#{$$}"

    File.open readme_ext, 'w' do |io|
      io.puts "# README.EXT -  -*- mode: RDoc; indent-tabs-mode: nil -*-"
      io.puts
      io.puts "This document explains how to make extension libraries for Ruby."
    end

    assert_equal 'rdoc', @RP.check_modeline(readme_ext)
  ensure
    File.unlink readme_ext
  end

  def test_check_modeline_no_modeline
    readme_ext = File.join Dir.tmpdir, "README.EXT.#{$$}"

    File.open readme_ext, 'w' do |io|
      io.puts "This document explains how to make extension libraries for Ruby."
    end

    assert_nil @RP.check_modeline(readme_ext)
  ensure
    File.unlink readme_ext
  end

  def test_class_for_binary
    rp = @RP.dup

    class << rp
      alias old_can_parse can_parse
    end

    def rp.can_parse(*args) nil end

    assert_nil @RP.for(nil, @binary_dat, nil, nil, nil)
  end

  def test_class_for_markup
    content = <<-CONTENT
# coding: utf-8 markup: rd
    CONTENT

    parser = @RP.for @top_level, __FILE__, content, @options, nil

    assert_kind_of @RP::RD, parser
  end

  def test_class_use_markup
    content = <<-CONTENT
# coding: utf-8 markup: rd
    CONTENT

    parser = @RP.use_markup content

    assert_equal @RP::RD, parser
  end

  def test_class_use_markup_markdown
    content = <<-CONTENT
# coding: utf-8 markup: markdown
    CONTENT

    parser = @RP.use_markup content

    assert_equal @RP::Ruby, parser
  end

  def test_class_use_markup_modeline
    content = <<-CONTENT
# -*- coding: utf-8 -*-
# markup: rd
    CONTENT

    parser = @RP.use_markup content

    assert_equal @RP::RD, parser
  end

  def test_class_use_markup_modeline_shebang
    content = <<-CONTENT
#!/bin/sh
/* -*- coding: utf-8 -*-
 * markup: rd
 */
    CONTENT

    parser = @RP.use_markup content

    assert_equal @RP::RD, parser
  end

  def test_class_use_markup_shebang
    content = <<-CONTENT
#!/usr/bin/env ruby
# coding: utf-8 markup: rd
    CONTENT

    parser = @RP.use_markup content

    assert_equal @RP::RD, parser
  end

  def test_class_use_markup_tomdoc
    content = <<-CONTENT
# coding: utf-8 markup: tomdoc
    CONTENT

    parser = @RP.use_markup content

    assert_equal @RP::Ruby, parser
  end

  def test_class_use_markup_none
    parser = @RP.use_markup ''

    assert_nil parser
  end

  def test_class_use_markup_unknown
    content = <<-CONTENT
# :markup: RDoc
    CONTENT

    parser = @RP.use_markup content

    assert_nil parser
  end

  def test_initialize
    @RP.new @top_level, @fn, '', @options, nil

    assert_equal @RP, @top_level.parser
  end

end
