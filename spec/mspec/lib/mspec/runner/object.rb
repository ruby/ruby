class Object
  def before(at=:each, &block)
    MSpec.current.before at, &block
  end

  def after(at=:each, &block)
    MSpec.current.after at, &block
  end

  def describe(mod, msg=nil, options=nil, &block)
    MSpec.describe mod, msg, &block
  end

  def it(msg, &block)
    MSpec.current.it msg, &block
  end

  def it_should_behave_like(desc)
    MSpec.current.it_should_behave_like desc
  end

  # For ReadRuby compatiability
  def doc(*a)
  end

  alias_method :context, :describe
  alias_method :specify, :it
end
