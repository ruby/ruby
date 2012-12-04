require 'rdoc/test_case'

class TestRDocParserChangeLog < RDoc::TestCase

  def setup
    super

    @tempfile  = Tempfile.new 'ChangeLog'
    @top_level = @store.add_file @tempfile.path
    @options   = RDoc::Options.new
    @stats     = RDoc::Stats.new @store, 0
  end

  def teardown
    @tempfile.close
  end

  def mu_pp obj
    s = ''
    s = PP.pp obj, s
    s = s.force_encoding Encoding.default_external if defined? Encoding
    s.chomp
  end

  def test_class_can_parse
    parser = RDoc::Parser::ChangeLog

    assert_equal parser, parser.can_parse('ChangeLog')

    assert_equal parser, parser.can_parse(@tempfile.path)
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
        list(:NOTE, item('e', para('five')), item('f', para('six'))),
    )
    expected.file = @top_level

    assert_equal expected, parser.create_document(groups)
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

    entries = {
      'Tue Dec  4 08:33:46 2012  Eric Hodel  <drbrain@segment7.net>' =>
        %w[one two],
      'Tue Dec  4 08:32:10 2012  Eric Hodel  <drbrain@segment7.net>' =>
        %w[three four],
      'Mon Dec  3 20:28:02 2012  Koichi Sasada  <ko1@atdot.net>' =>
        %w[five six],
    }

    expected = {
      '2012-12-04' => [
        ['Tue Dec  4 08:33:46 2012  Eric Hodel  <drbrain@segment7.net>',
          %w[one two]],
        ['Tue Dec  4 08:32:10 2012  Eric Hodel  <drbrain@segment7.net>',
          %w[three four]]],
      '2012-12-03' => [
        ['Mon Dec  3 20:28:02 2012  Koichi Sasada  <ko1@atdot.net>',
          %w[five six]]],
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

Other note that will be ignored

    ChangeLog

    expected = {
      'Tue Dec  4 08:33:46 2012  Eric Hodel  <drbrain@segment7.net>' => [
        'README.EXT:  Converted to RDoc format',
        'README.EXT.ja:  ditto',
      ],
      'Mon Dec  3 20:28:02 2012  Koichi Sasada  <ko1@atdot.net>' => [
        'compile.c (iseq_specialized_instruction): change condition of ' +
          'using `opt_send_simple\'. More method invocations can be simple.',
      ],
    }

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

  def util_parser content = ''
    RDoc::Parser::ChangeLog.new \
      @top_level, @tempfile.path, content, @options, @stats
  end

end

