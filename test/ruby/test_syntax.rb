require 'test/unit'

class TestSyntax < Test::Unit::TestCase
  def valid_syntax?(code, fname)
    code = code.dup.force_encoding("ascii-8bit")
    code.sub!(/\A(?:\xef\xbb\xbf)?(\s*\#.*$)*(\n)?/n) {
      "#$&#{"\n" if $1 && !$2}BEGIN{throw tag, :ok}\n"
    }
    code.force_encoding("us-ascii")
    catch {|tag| eval(code, binding, fname, 0)}
  rescue SyntaxError
    false
  end

  def test_syntax
    assert_nothing_raised(Exception) do
      for script in Dir[File.expand_path("../../../{lib,sample,ext,test}/**/*.rb", __FILE__)].sort
        assert(valid_syntax?(IO::read(script), script))
      end
    end
  end
end
