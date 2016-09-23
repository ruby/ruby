# coding: US-ASCII
# frozen_string_literal: false

require 'rdoc/test_case'

class TestRDocEncoding < RDoc::TestCase

  def setup
    super

    @tempfile = Tempfile.new 'test_rdoc_encoding'
  end

  def teardown
    @tempfile.close!

    super
  end

  def test_class_read_file
    @tempfile.write "hi everybody"
    @tempfile.flush

    assert_equal "hi everybody", RDoc::Encoding.read_file(@tempfile.path, nil)
  end

  def test_class_read_file_encoding
    expected = "# coding: utf-8\nhi everybody"

    @tempfile.write expected
    @tempfile.flush

    contents = RDoc::Encoding.read_file @tempfile.path, Encoding::UTF_8
    assert_equal "hi everybody", contents
    assert_equal Encoding::UTF_8, contents.encoding
  end

  def test_class_read_file_encoding_convert
    content = ""
    content.encode! 'ISO-8859-1'
    content << "# coding: ISO-8859-1\nhi \xE9verybody"

    @tempfile.write content
    @tempfile.flush

    contents = RDoc::Encoding.read_file @tempfile.path, Encoding::UTF_8
    assert_equal Encoding::UTF_8, contents.encoding
    assert_equal "hi \u00e9verybody", contents.sub("\r", '')
  end

  def test_class_read_file_encoding_fail
    @tempfile.write "# coding: utf-8\n\317\200" # pi
    @tempfile.flush

    contents = :junk

    _, err = verbose_capture_io do
      contents = RDoc::Encoding.read_file @tempfile.path, Encoding::US_ASCII
    end

    assert_nil contents

    assert_match %r%^unable to convert%, err
  end

  def test_class_read_file_encoding_fancy
    expected = "# -*- coding: utf-8; fill-column: 74 -*-\nhi everybody"
    expected.encode! Encoding::UTF_8

    @tempfile.write expected
    @tempfile.flush

    contents = RDoc::Encoding.read_file @tempfile.path, Encoding::UTF_8
    assert_equal "hi everybody", contents
    assert_equal Encoding::UTF_8, contents.encoding
  end

  def test_class_read_file_encoding_force_transcode
    @tempfile.write "# coding: utf-8\n\317\200" # pi
    @tempfile.flush

    contents = RDoc::Encoding.read_file @tempfile.path, Encoding::US_ASCII, true

    assert_equal '?', contents
    assert_equal Encoding::US_ASCII, contents.encoding
  end

  def test_class_read_file_encoding_guess
    path = File.expand_path '../test.ja.txt', __FILE__
    content = RDoc::Encoding.read_file path, Encoding::UTF_8

    assert_equal Encoding::UTF_8, content.encoding
  end

  def test_class_read_file_encoding_invalid
    @tempfile.write "# coding: ascii\nM\xE4r"
    @tempfile.flush

    contents = :junk
    _, err = verbose_capture_io do
      contents = RDoc::Encoding.read_file @tempfile.path, Encoding::UTF_8
    end

    assert_equal "unable to convert \"\\xE4\" on US-ASCII for #{@tempfile.path}, skipping\n", err

    assert_nil contents
  end

  def test_class_read_file_encoding_with_signature
    @tempfile.write "\xEF\xBB\xBFhi everybody"
    @tempfile.flush

    bug3360 = '[ruby-dev:41452]'
    content = RDoc::Encoding.read_file @tempfile.path, Encoding::UTF_8
    assert_equal Encoding::UTF_8, content.encoding, bug3360
    assert_equal "hi everybody", content, bug3360
  end

  def test_class_read_file_encoding_iso_2022_jp
    input = "# coding: ISO-2022-JP\n:\e$B%3%^%s%I\e(B:"

    @tempfile.write input
    @tempfile.flush

    contents = RDoc::Encoding.read_file @tempfile.path, Encoding::UTF_8

    expected = ":\xe3\x82\xb3\xe3\x83\x9e\xe3\x83\xb3\xe3\x83\x89:"
    expected.force_encoding Encoding::UTF_8

    assert_equal expected, contents
    assert_equal Encoding::UTF_8, contents.encoding
  end

  def test_class_set_encoding
    s = "# coding: UTF-8\n"
    RDoc::Encoding.set_encoding s

    # sanity check for 1.8

    assert_equal Encoding::UTF_8, s.encoding

    s = "#!/bin/ruby\n# coding: UTF-8\n"
    RDoc::Encoding.set_encoding s

    assert_equal Encoding::UTF_8, s.encoding

    s = "<?xml version='1.0' encoding='UTF-8'?>\n"
    expected = s.encoding
    RDoc::Encoding.set_encoding s

    assert_equal Encoding::UTF_8, s.encoding

    s = "<?xml version='1.0' encoding=\"UTF-8\"?>\n"
    expected = s.encoding
    RDoc::Encoding.set_encoding s

    assert_equal Encoding::UTF_8, s.encoding
  end

  def test_class_set_encoding_strip
    s = "# coding: UTF-8\n# more comments"

    RDoc::Encoding.set_encoding s

    assert_equal "# more comments", s

    s = "#!/bin/ruby\n# coding: UTF-8\n# more comments"

    RDoc::Encoding.set_encoding s

    assert_equal "#!/bin/ruby\n# more comments", s
  end

  def test_class_set_encoding_bad
    s = ""
    expected = s.encoding
    RDoc::Encoding.set_encoding s

    assert_equal expected, s.encoding

    s = "# vim:set fileencoding=utf-8:\n"
    expected = s.encoding
    RDoc::Encoding.set_encoding s

    assert_equal expected, s.encoding

    s = "# vim:set fileencoding=utf-8:\n"
    expected = s.encoding
    RDoc::Encoding.set_encoding s

    assert_equal expected, s.encoding

    assert_raises ArgumentError do
      RDoc::Encoding.set_encoding "# -*- encoding: undecided -*-\n"
    end
  end

  def test_skip_frozen_string_literal
    expected = "# frozen_string_literal: false\nhi everybody"

    @tempfile.write expected
    @tempfile.flush

    contents = RDoc::Encoding.read_file @tempfile.path, Encoding::UTF_8
    assert_equal "hi everybody", contents
    assert_equal Encoding::UTF_8, contents.encoding
  end

  def test_skip_frozen_string_literal_after_coding
    expected = "# coding: utf-8\n# frozen-string-literal: false\nhi everybody"

    @tempfile.write expected
    @tempfile.flush

    contents = RDoc::Encoding.read_file @tempfile.path, Encoding::UTF_8
    assert_equal "hi everybody", contents
    assert_equal Encoding::UTF_8, contents.encoding
  end

  def test_skip_frozen_string_literal_before_coding
    expected = "# frozen_string_literal: false\n# coding: utf-8\nhi everybody"

    @tempfile.write expected
    @tempfile.flush

    contents = RDoc::Encoding.read_file @tempfile.path, Encoding::UTF_8
    assert_equal "hi everybody", contents
    assert_equal Encoding::UTF_8, contents.encoding
  end

  def test_sanity
    assert_equal Encoding::US_ASCII, ''.encoding,
                 'If this file is not ASCII tests may incorrectly pass'
  end

end
