class Object
  private def before(at = :each, &block)
    MSpec.current.before at, &block
  end

  private def after(at = :each, &block)
    MSpec.current.after at, &block
  end

  private def describe(description, options = nil, &block)
    MSpec.describe description, options, &block
  end

  private def it(desc, &block)
    MSpec.current.it desc, &block
  end

  private def it_should_behave_like(desc)
    MSpec.current.it_should_behave_like desc
  end

  alias_method :context, :describe
  private :context
  alias_method :specify, :it
  private :specify
end
