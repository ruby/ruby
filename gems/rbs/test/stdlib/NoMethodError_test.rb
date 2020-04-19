require_relative "test_helper"

class NoMethodErrorTest < StdlibTest
  target NoMethodError
  using hook.refinement

  def test_new
    NoMethodError.new()
    NoMethodError.new(ToStr.new("Message"), "foo")
  end

  def test_args
    begin
      [].aaaaaaaaaaa(1, foo: 123, **{ hello: :world })
    rescue NoMethodError => exn
      exn
    end

    exn.args
  end

  def test_private_call?
    begin
      [].aaaaaaaaaaa(1, foo: 123, **{ hello: :world })
    rescue NoMethodError => exn
      exn
    end

    exn.private_call?
  end
end
