require_relative "test_helper"

class MatchDataTest < StdlibTest
  target MatchData
  using hook.refinement

  # test_==
  def test_equal
    foo = 'foo'
    foo.match('f') == foo.match('f')
  end

  # test_[]
  def test_square_bracket
    /(?<first>foo)(?<second>bar)(?<third>Baz)?/ =~ "foobarbaz"
    $~[0]
    $~[3]
    $~[0..3]
    $~[0, 4]
    $~['first']
    $~['third']
    $~[:first]
    $~[:third]
  end

  # test_begin
  def test_begin
    /(?<first>foo)(?<second>bar)(?<third>Baz)?/ =~ "foobarbaz"
    $~.begin 0
    $~.begin 3
    $~.begin 'first'
    $~.begin 'third'
    $~.begin :first
    $~.begin :third
  end

  def test_caputres
    /(?<first>foo)(?<second>bar)(?<third>Baz)?/ =~ "foobarbaz"
    $~.captures
  end

  def test_end
    /(?<first>foo)(?<second>bar)(?<third>Baz)?/ =~ "foobarbaz"
    $~.end 0
    $~.end 3
    $~.end 'first'
    $~.end 'third'
    $~.end :first
    $~.end :third 
  end

  def test_eql?
    foo = 'foo'
    foo.match('f').eql? foo.match('f')
  end

  def test_hash
    'foo'.match('f').hash
  end

  def test_inspect
    'foo'.match('f').inspect
  end

  def test_length
    'foo'.match('f').length
  end

  def test_named_captures
    'foo'.match('(?<a>foo)').named_captures
  end

  def test_names
    'foo'.match('(?<a>foo)').names
  end

  def test_offset
    /(?<first>foo)(?<second>bar)(?<third>Baz)?/ =~ "foobarbaz"
    $~.offset 0
    $~.offset 3
    $~.offset 'first'
    $~.offset 'third'
    $~.offset :first
    $~.offset :third 
  end

  def test_post_match
    'foo'.match('f').post_match
  end

  def test_pre_match
    'foo'.match('o').pre_match
  end

  def test_regexp
    'foo'.match('f').regexp
  end

  def test_size
    'foo'.match('f').size
  end

  def test_string
    'foo'.match('f').string
  end

  def test_to_a
    /(?<first>foo)(?<second>bar)(?<third>Baz)?/ =~ "foobarbaz"
    $~.to_a
  end

  def test_to_s
    'foo'.match('f').to_s
  end

  def test_values_at
    /(?<first>foo)(?<second>bar)(?<third>Baz)?/ =~ "foobarbaz"
    $~.values_at 0
    $~.values_at 3
    $~.values_at 'first'
    $~.values_at 'third'
    $~.values_at :first
    $~.values_at :third
  end
end