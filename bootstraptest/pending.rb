assert_equal 'ok', %q{
  1.times{
    eval("break")
  }
  :ok
}, '[ruby-dev:32525]'

assert_equal "ok", %q{
  module Foo
  end

  begin
    def foo(&b)
      Foo.module_eval &b
    end
    foo{
      def bar
      end
    }
    bar
  rescue NoMethodError
    :ok
  end
}, '[ruby-core:14378]'

