require_relative '../../spec_helper'


describe "Performance warnings" do
  guard -> { ruby_version_is("3.4") || RUBY_ENGINE == "truffleruby" } do
    # Optimising Integer, Float or Symbol methods is kind of implementation detail
    # but multiple implementations do so. So it seems reasonable to have a test case
    # for at least one such common method.
    # See https://bugs.ruby-lang.org/issues/20429
    context "when redefined optimised methods" do
      it "emits performance warning for redefining Integer#+" do
        code = <<~CODE
          Warning[:performance] = true

          class Integer
            ORIG_METHOD = instance_method(:+)

            def +(...)
              ORIG_METHOD.bind(self).call(...)
            end
          end
        CODE

        ruby_exe(code, args: "2>&1").should.include?("warning: Redefining 'Integer#+' disables interpreter and JIT optimizations")
      end
    end
  end
end
