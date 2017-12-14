require File.expand_path('../helper', __FILE__)

class TestRakeInvocationChain < Rake::TestCase
  include Rake

  def setup
    super

    @empty = InvocationChain.empty

    @first_member = "A"
    @second_member = "B"
    @one = @empty.append(@first_member)
    @two = @one.append(@second_member)
  end

  def test_conj_on_invocation_chains
    list = InvocationChain.empty.conj("B").conj("A")
    assert_equal InvocationChain.make("A", "B"), list
    assert_equal InvocationChain, list.class
  end

  def test_make_on_invocation_chains
    assert_equal @empty, InvocationChain.make()
    assert_equal @one, InvocationChain.make(@first_member)
    assert_equal @two, InvocationChain.make(@second_member, @first_member)
  end

  def test_append_with_one_argument
    chain = @empty.append("A")

    assert_equal 'TOP => A', chain.to_s # HACK
  end

  def test_append_one_circular
    ex = assert_raises RuntimeError do
      @one.append(@first_member)
    end
    assert_match(/circular +dependency/i, ex.message)
    assert_match(/A.*=>.*A/, ex.message)
  end

  def test_append_two_circular
    ex = assert_raises RuntimeError do
      @two.append(@first_member)
    end
    assert_match(/A.*=>.*B.*=>.*A/, ex.message)
  end

  def test_member_eh_one
    assert @one.member?(@first_member)
  end

  def test_member_eh_two
    assert @two.member?(@first_member)
    assert @two.member?(@second_member)
  end

  def test_to_s_empty
    assert_equal "TOP", @empty.to_s
    assert_equal "TOP => A", @one.to_s
  end

end
