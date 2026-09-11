require 'test/unit'
require 'erb'

class TestERBEscape < Test::Unit::TestCase
  def test_html_escape
    assert_equal(" !&quot;\#$%&amp;&#39;()*+,-./0123456789:;&lt;=&gt;?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~",
                 ERB::Util.html_escape(" !\"\#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"))

    assert_equal("", ERB::Util.html_escape(""))
    assert_equal("abc", ERB::Util.html_escape("abc"))
    assert_equal("&lt;&lt;", ERB::Util.html_escape("<\<"))
    assert_equal("&#39;&amp;&quot;&gt;&lt;" * 10, ERB::Util.html_escape("'&\"><" * 10))

    assert_equal("", ERB::Util.html_escape(nil))
    assert_equal("123", ERB::Util.html_escape(123))

    assert_equal(65536+5, ERB::Util.html_escape("x"*65536 + "&").size)
    assert_equal(65536+5, ERB::Util.html_escape("&" + "x"*65536).size)
  end

  def test_html_escape_string_subclass
    klass = Class.new(String) do
      def to_s
        "<to_s>"
      end
    end
    assert_equal("&lt;b&gt;", ERB::Util.html_escape(klass.new("<b>")))
  end

  def test_html_escape_to_s
    object = Object.new
    def object.to_s
      "object"
    end
    assert_equal("object", ERB::Util.html_escape(object))
  end

  def test_html_escape_extension
    assert_nil(ERB::Util.method(:html_escape).source_location)
  end if RUBY_ENGINE == 'ruby'

  def test_util_html_escape_in_ractor
    assert_ractor(<<~RUBY, require: 'erb')
      r = Ractor.new do
        ERB::Util.html_escape("<script>")
      end
      assert_equal("&lt;script&gt;", r.value)
    RUBY
  end

  def test_simd_coverage
    16.times do |i|
      str = "#{'.' * i}<#{'.' * (16-i-1)}#{'<' * 16}"
      esc = "#{'.' * i}&lt;#{'.'* (16-i-1)}#{'&lt;' * 16}"
      assert_equal esc, h(str)
    end

    assert_equal '&lt;' * 32, h('<' * 32)
  end

  private

  def h(...)
    ERB::Util.html_escape(...)
  end
end
