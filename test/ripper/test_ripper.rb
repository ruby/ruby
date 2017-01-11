# frozen_string_literal: false
begin
  require 'ripper'
  require 'test/unit'
  ripper_test = true
  module TestRipper; end
rescue LoadError
end

class TestRipper::Ripper < Test::Unit::TestCase

  def setup
    @ripper = Ripper.new '1 + 1'
  end

  def test_column
    assert_nil @ripper.column
  end

  def test_encoding
    assert_equal Encoding::UTF_8, @ripper.encoding
    ripper = Ripper.new('# coding: iso-8859-15')
    ripper.parse
    assert_equal Encoding::ISO_8859_15, ripper.encoding
    ripper = Ripper.new('# -*- coding: iso-8859-15 -*-')
    ripper.parse
    assert_equal Encoding::ISO_8859_15, ripper.encoding
  end

  def test_end_seen_eh
    @ripper.parse
    assert_not_predicate @ripper, :end_seen?
    ripper = Ripper.new('__END__')
    ripper.parse
    assert_predicate ripper, :end_seen?
  end

  def test_filename
    assert_equal '(ripper)', @ripper.filename
    filename = "ripper"
    ripper = Ripper.new("", filename)
    filename.clear
    assert_equal "ripper", ripper.filename
  end

  def test_lineno
    assert_nil @ripper.lineno
  end

  def test_parse
    assert_nil @ripper.parse
  end

  def test_yydebug
    assert_not_predicate @ripper, :yydebug
  end

  def test_yydebug_equals
    @ripper.yydebug = true

    assert_predicate @ripper, :yydebug
  end

  def test_regexp_with_option
    bug11932 = '[ruby-core:72638] [Bug #11932]'
    src = '/[\xC0-\xF0]/u'.force_encoding(Encoding::UTF_8)
    ripper = Ripper.new(src)
    ripper.parse
    assert_predicate(ripper, :error?)
    src = '/[\xC0-\xF0]/n'.force_encoding(Encoding::UTF_8)
    ripper = Ripper.new(src)
    ripper.parse
    assert_not_predicate(ripper, :error?, bug11932)
  end

  def test_regexp_enc_error
    assert_separately(%w[-rripper], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      bug12651 = '[ruby-core:76397] [Bug #12651]'
      src = <<-END
<%- @title = '\u{5bff 9650 7121}' -%>
<%- content_for :foo, render(partial: 'bar', locals: {baz: 2}) -%>

<div class="dead beef">
  <h2 class="dead beef">\u{5bff 9650 7121}</h2>
</div>
<div class="dead beef">\u{5bff 9650 7121 3002}<br class="dead beef">\u{5bff 9650 7121 3002}</div>

<div class="dead beef">
  <div class="dead beef">
    <label class="dead beef">\u{5bff 9650 7121}</label>
    <div class="dead beef">
      <div class="dead beef"><%= @baz %></div>
    </div>
  </div>
</div>
      END
      assert_nil(Ripper.sexp(src), bug12651)
    end;
  end

  # https://bugs.jruby.org/4176
  def test_dedent_string
    col = Ripper.dedent_string '  hello', 0
    assert_equal 0, col
    col = Ripper.dedent_string '  hello', 2
    assert_equal 2, col
    col = Ripper.dedent_string '  hello', 4
    assert_equal 2, col

    # lexing a squiggly heredoc triggers Ripper#dedent_string use
    src = <<-END
puts <<~end
  hello
end
    END

    assert_nothing_raised { Ripper.lex src }
  end

  class TestInput < self
    Input = Struct.new(:lines) do
      def gets
        lines.shift
      end
    end

    def setup
      @ripper = Ripper.new(Input.new(["1 + 1"]))
    end

    def test_invalid_gets
      ripper = assert_nothing_raised {Ripper.new(Input.new([0]))}
      assert_raise(TypeError) {ripper.parse}
    end
  end

end if ripper_test
