# frozen_string_literal: true
require_relative 'helper'

class TestRDocParserChangeLog < RDoc::TestCase

  def setup
    super

    @tempfile  = Tempfile.new 'ChangeLog'
    @top_level = @store.add_file @tempfile.path
    @options   = RDoc::Options.new
    @stats     = RDoc::Stats.new @store, 0
  end

  def teardown
    @tempfile.close!

    super
  end

  def test_class_can_parse
    parser = RDoc::Parser::ChangeLog

    temp_dir do
      FileUtils.touch 'ChangeLog'
      assert_equal parser, parser.can_parse('ChangeLog')

      assert_equal parser, parser.can_parse(@tempfile.path)

      FileUtils.touch 'ChangeLog.rb'
      assert_equal RDoc::Parser::Ruby, parser.can_parse('ChangeLog.rb')
    end
  end

  def test_continue_entry_body
    parser = util_parser

    entry_body = ['a'.dup]

    parser.continue_entry_body entry_body, 'b'

    assert_equal ['a b'], entry_body
  end

  def test_continue_entry_body_empty
    parser = util_parser

    entry_body = []

    parser.continue_entry_body entry_body, ''

    assert_empty entry_body
  end

  def test_continue_entry_body_function
    parser = util_parser

    entry_body = ['file: (func1)'.dup]

    parser.continue_entry_body entry_body, '(func2): blah'

    assert_equal ['file: (func1, func2): blah'], entry_body
  end

  def test_create_document
    parser = util_parser

    groups = {
      '2012-12-04' => [
        ['Tue Dec  4 08:33:46 2012  Eric Hodel  <drbrain@segment7.net>',
          %w[a:one b:two]],
        ['Tue Dec  4 08:32:10 2012  Eric Hodel  <drbrain@segment7.net>',
          %w[c:three d:four]]],
      '2012-12-03' => [
        ['Mon Dec  3 20:28:02 2012  Koichi Sasada  <ko1@atdot.net>',
          %w[e:five f:six]]],
    }

    expected =
      doc(
        head(1, File.basename(@tempfile.path)),
        blank_line,
        head(2, '2012-12-04'),
        blank_line,
        head(3, 'Tue Dec  4 08:33:46 2012  Eric Hodel  <drbrain@segment7.net>'),
        blank_line,
        list(:NOTE, item('a', para('one')), item('b', para('two'))),
        head(3, 'Tue Dec  4 08:32:10 2012  Eric Hodel  <drbrain@segment7.net>'),
        blank_line,
        list(:NOTE, item('c', para('three')), item('d', para('four'))),
        head(2, '2012-12-03'),
        blank_line,
        head(3, 'Mon Dec  3 20:28:02 2012  Koichi Sasada  <ko1@atdot.net>'),
        blank_line,
        list(:NOTE, item('e', para('five')), item('f', para('six'))))

    expected.file = @top_level

    document = parser.create_document(groups)

    assert_equal expected, document

    assert_equal 2, document.omit_headings_below

    headings = document.parts.select do |part|
      RDoc::Markup::Heading === part and part.level == 2
    end

    refute headings.all? { |heading| heading.text.frozen? }
  end

  def test_create_entries
    parser = util_parser

    entries = [
      ['Tue Dec  1 02:03:04 2012  Eric Hodel  <drbrain@segment7.net>',
        %w[a:one b:two]],
      ['Tue Dec  5 06:07:08 2012  Eric Hodel  <drbrain@segment7.net>',
        %w[c:three d:four]],
    ]

    expected = [
      head(3, 'Tue Dec  1 02:03:04 2012  Eric Hodel  <drbrain@segment7.net>'),
      blank_line,
      list(:NOTE, item('a', para('one')), item('b', para('two'))),
      head(3, 'Tue Dec  5 06:07:08 2012  Eric Hodel  <drbrain@segment7.net>'),
      blank_line,
      list(:NOTE, item('c', para('three')), item('d', para('four'))),
    ]

    entries = parser.create_entries(entries)
    assert_equal expected, entries
  end

  def test_create_entries_colons
    parser = util_parser

    entries = [
      ['Wed Dec  5 12:17:11 2012  Naohisa Goto  <ngotogenome@gmail.com>',
        ['func.rb (DL::Function#bind): log stuff [ruby-core:50562]']],
    ]

    expected = [
      head(3,
           'Wed Dec  5 12:17:11 2012  Naohisa Goto  <ngotogenome@gmail.com>'),
      blank_line,
      list(:NOTE,
           item('func.rb (DL::Function#bind)',
                para('log stuff [ruby-core:50562]')))]

    assert_equal expected, parser.create_entries(entries)
  end

  def test_create_items
    parser = util_parser

    items = [
	    'README.EXT:  Converted to RDoc format',
	    'README.EXT.ja:  ditto',
    ]

    expected =
      list(:NOTE,
        item('README.EXT',
          para('Converted to RDoc format')),
        item('README.EXT.ja',
          para('ditto')))

    assert_equal expected, parser.create_items(items)
  end

  def test_group_entries
    parser = util_parser

    entries = [
      [ 'Tue Dec  4 08:33:46 2012  Eric Hodel  <drbrain@segment7.net>',
        %w[one two]],
      [ 'Tue Dec  4 08:32:10 2012  Eric Hodel  <drbrain@segment7.net>',
        %w[three four]],
      [ 'Mon Dec  3 20:28:02 2012  Koichi Sasada  <ko1@atdot.net>',
        %w[five six]],
      [ '2008-01-30  H.J. Lu  <hongjiu.lu@intel.com>',
        %w[seven eight]]]

    expected = {
      '2012-12-04' => [
        ['Tue Dec  4 08:33:46 2012  Eric Hodel  <drbrain@segment7.net>',
          %w[one two]],
        ['Tue Dec  4 08:32:10 2012  Eric Hodel  <drbrain@segment7.net>',
          %w[three four]]],
      '2012-12-03' => [
        ['Mon Dec  3 20:28:02 2012  Koichi Sasada  <ko1@atdot.net>',
          %w[five six]]],
      '2008-01-30' => [
        ['2008-01-30  H.J. Lu  <hongjiu.lu@intel.com>',
          %w[seven eight]]],
    }

    assert_equal expected, parser.group_entries(entries)
  end

  def test_parse_entries
    parser = util_parser <<-ChangeLog
Tue Dec  4 08:33:46 2012  Eric Hodel  <drbrain@segment7.net>

	* README.EXT:  Converted to RDoc format
	* README.EXT.ja:  ditto

Mon Dec  3 20:28:02 2012  Koichi Sasada  <ko1@atdot.net>

	* compile.c (iseq_specialized_instruction):
	  change condition of using `opt_send_simple'.
	  More method invocations can be simple.

commit\ 8187228de0142d3ac7950b7d977c2849e934c637

Other note that will be ignored

    ChangeLog

    expected = [
      [ 'Tue Dec  4 08:33:46 2012  Eric Hodel  <drbrain@segment7.net>',
        [ 'README.EXT:  Converted to RDoc format',
          'README.EXT.ja:  ditto']],
      [ 'Mon Dec  3 20:28:02 2012  Koichi Sasada  <ko1@atdot.net>',
        [ 'compile.c (iseq_specialized_instruction): change condition of ' +
          'using `opt_send_simple\'. More method invocations can be simple.']]]

    assert_equal expected, parser.parse_entries
  end

  def test_parse_entries_bad_time
    parser = util_parser <<-ChangeLog
2008-01-30  H.J. Lu  <hongjiu.lu@intel.com>

        PR libffi/34612
        * src/x86/sysv.S (ffi_closure_SYSV): Pop 4 byte from stack when
        returning struct.

    ChangeLog

    expected = [
      [ '2008-01-30  H.J. Lu  <hongjiu.lu@intel.com>',
        [ 'src/x86/sysv.S (ffi_closure_SYSV): Pop 4 byte from stack when ' +
          'returning struct.']]
    ]

    assert_equal expected, parser.parse_entries
  end

  def test_parse_entries_gnu
    parser = util_parser <<-ChangeLog
1998-08-17  Richard Stallman  <rms@gnu.org>

* register.el (insert-register): Return nil.
(jump-to-register): Likewise.

* sort.el (sort-subr): Return nil.

* keyboard.c (menu_bar_items, tool_bar_items)
(Fexecute_extended_command): Deal with 'keymap' property.
    ChangeLog

    expected = [
      [ '1998-08-17  Richard Stallman  <rms@gnu.org>',
        [ 'register.el (insert-register): Return nil.',
          '(jump-to-register): Likewise.',
          'sort.el (sort-subr): Return nil.',
          'keyboard.c (menu_bar_items, tool_bar_items, ' +
          'Fexecute_extended_command): Deal with \'keymap\' property.']]]

    assert_equal expected, parser.parse_entries
  end

  def test_parse_entries_git
    parser = util_parser <<-ChangeLog
commit\ 709bed2afaee50e2ce803f87bf1ee8291bea41e3
  Author: git <svn-admin@ruby-lang.org>
  Date:   2021-01-21 01:03:52 +0900

    * 2021-01-21 [ci skip]
ChangeLog

    expected = [
      [ "709bed2afaee50e2ce80",
       [ "git", "svn-admin@ruby-lang.org",
         "2021-01-21 01:03:52 +0900",
         "* 2021-01-21 [ci skip]\n"]]]

    assert_equal expected, parser.parse_entries
  end

  def test_scan
    parser = util_parser <<-ChangeLog
Tue Dec  4 08:32:10 2012  Eric Hodel  <drbrain@segment7.net>

	* lib/rdoc/ri/driver.rb:  Fixed ri page display for files with
	  extensions.
	* test/rdoc/test_rdoc_ri_driver.rb:  Test for above

Mon Dec  3 20:37:22 2012  Koichi Sasada  <ko1@atdot.net>

	* vm_exec.c: check VM_COLLECT_USAGE_DETAILS.

    ChangeLog

    parser.scan

    expected = doc(
      head(1, File.basename(@tempfile.path)),
      blank_line,
      head(2, '2012-12-04'),
      blank_line,
      head(3, 'Tue Dec  4 08:32:10 2012  Eric Hodel  <drbrain@segment7.net>'),
      blank_line,
      list(:NOTE,
        item('lib/rdoc/ri/driver.rb', para('Fixed ri page display for ' +
                       'files with extensions.')),
        item('test/rdoc/test_rdoc_ri_driver.rb', para('Test for above'))),
      head(2, '2012-12-03'),
      blank_line,
      head(3, 'Mon Dec  3 20:37:22 2012  Koichi Sasada  <ko1@atdot.net>'),
      blank_line,
      list(:NOTE,
        item('vm_exec.c', para('check VM_COLLECT_USAGE_DETAILS.'))))

    expected.file = @top_level

    assert_equal expected, @top_level.comment
  end

  def test_scan_git
    parser = util_parser <<-ChangeLog
commit\ 38816887962ec167ee46acf500f68df5c3013163
Author: git <svn-admin@ruby-lang.org>
Date:   Sun Jan 24 14:35:51 2021 +0900

    * 2021-01-24 [ci skip]

commit\ db7d0b89f6eca66cc7eb155c95f9123133da1ffc
Author: git <svn-admin@ruby-lang.org>
Date:   Sat, 23 Jan 2021 06:01:39 +0900

    * 2021-01-23 [ci skip]

commit\ a3efbda7128ef20b55505b32d1608ea48f80af4a
Author: git <svn-admin@ruby-lang.org>
Date:   2021-01-22T02:49:39+09:00

    * 2021-01-22 [ci skip]

commit\ 709bed2afaee50e2ce803f87bf1ee8291bea41e3
  Author: git <svn-admin@ruby-lang.org>
  Date:   2021-01-21 01:03:52 +0900

    * 2021-01-21 [ci skip]

commit\ a8dc5156e183489c5121fb1759bda5d9406d9175
  Author: git <svn-admin@ruby-lang.org>
  Date:   2021-01-20 01:58:26 +0900

    * 2021-01-20 [ci skip]

commit\ de5f8a92d5001799bedb3b1a271a2d9b23c6c8fb
  Author: Masataka Pocke Kuwabara <kuwabara@pocke.me>
  Date:   2021-01-01 14:25:08 +0900

    Make args info for RubyVM::AST to available on endless method without parens

    Problem
    ===

    Arguments information is missing for endless method without parens.
    For example:

    ```ruby
    # ok
    ```

    It causes an error if a program expects `args` node exists.

    Solution
    ===

    Call `new_args` on this case.
ChangeLog

    parser.scan

    expected = doc(
      head(1, File.basename(@tempfile.path)),
      blank_line,
      head(2, '2021-01-24'),
      blank_line,
      log_entry(nil, '38816887962ec167ee46',
                'git', 'svn-admin@ruby-lang.org', 'Sun Jan 24 14:35:51 2021 +0900',
                [list(:BULLET, item(nil, para('2021-01-24 [ci skip]')))]),
      head(2, '2021-01-23'),
      blank_line,
      log_entry(nil, 'db7d0b89f6eca66cc7eb',
                'git', 'svn-admin@ruby-lang.org', 'Sat, 23 Jan 2021 06:01:39 +0900',
                [list(:BULLET, item(nil, para('2021-01-23 [ci skip]')))]),
      head(2, '2021-01-22'),
      blank_line,
      log_entry(nil, 'a3efbda7128ef20b5550',
                'git', 'svn-admin@ruby-lang.org', '2021-01-22T02:49:39+09:00',
                [list(:BULLET, item(nil, para('2021-01-22 [ci skip]')))]),
      head(2, '2021-01-21'),
      blank_line,
      log_entry(nil, '709bed2afaee50e2ce80',
                'git', 'svn-admin@ruby-lang.org', '2021-01-21 01:03:52 +0900',
                [list(:BULLET, item(nil, para('2021-01-21 [ci skip]')))]),
      head(2, '2021-01-20'),
      blank_line,
      log_entry(nil, 'a8dc5156e183489c5121',
                'git', 'svn-admin@ruby-lang.org', '2021-01-20 01:58:26 +0900',
                [list(:BULLET, item(nil, para('2021-01-20 [ci skip]')))]),
      head(2, '2021-01-01'),
      blank_line,
      log_entry(nil, 'de5f8a92d5001799bedb',
                'Masataka Pocke Kuwabara', 'kuwabara@pocke.me', '2021-01-01 14:25:08 +0900',
                [head(4, 'Make args info for RubyVM::AST to available on endless method without parens'),
                 head(5, 'Problem'),
                 para("Arguments information is missing for endless method without parens.\n" +
                      "For example:"),
                 verb("# ok\n").tap {|v| v.format = :ruby},
                 para('It causes an error if a program expects <code>args</code> node exists.'),
                 head(5, 'Solution'),
                 para('Call <code>new_args</code> on this case.')]))

    expected.file = @top_level

    assert_equal expected, @top_level.comment
  end

  def test_scan_git_commit_date
    parser = util_parser <<-ChangeLog
commit\ ee1e690a2df901adb279d7a63fbd92c64e0a5ae6
  Author:     Igor Zubkov <igor.zubkov@gmail.com>
  AuthorDate: 2016-10-25 03:56:11 +0900
  Commit:     Nobuyoshi Nakada <nobu@ruby-lang.org>
  CommitDate: 2021-01-07 13:40:42 +0900

    We don't need "require 'uri'" after "require 'net/http'".

commit\ 4d0985a7bd8f591dff4b430e288bfd83af782e51
  Author:     git <svn-admin@ruby-lang.org>
  AuthorDate: 2021-01-07 10:21:34 +0900
  Commit:     git <svn-admin@ruby-lang.org>
  CommitDate: 2021-01-07 10:21:34 +0900

    * 2021-01-07 [ci skip]
ChangeLog

    parser.scan

    expected = doc(
      head(1, File.basename(@tempfile.path)),
      blank_line,
      head(2, "2021-01-07"),
      blank_line,
      log_entry(nil, 'ee1e690a2df901adb279',
                'Igor Zubkov', 'igor.zubkov@gmail.com',
                '2016-10-25 03:56:11 +0900',
                [head(4, %[We don't need "require 'uri'" after "require 'net/http'".])]),
      log_entry(nil, '4d0985a7bd8f591dff4b',
                'git', 'svn-admin@ruby-lang.org',
                '2021-01-07 10:21:34 +0900',
                [list(:BULLET, item(nil, para("2021-01-07 [ci skip]")))]))

    expected.file = @top_level

    assert_equal expected, @top_level.comment
  end

  def util_parser content = ''
    RDoc::Parser::ChangeLog.new \
      @top_level, @tempfile.path, content, @options, @stats
  end

  def log_entry(*a)
    RDoc::Parser::ChangeLog::Git::LogEntry.new(*a)
  end
end

