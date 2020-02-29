require_relative '../spec_helper'
require_relative 'fixtures/delegation'

ruby_version_is "2.7" do
  describe "delegation with def(...)" do
    it "delegates rest and kwargs" do
      a = Class.new(DelegationSpecs::Target)
      a.class_eval(<<-RUBY)
        def delegate(...)
          target(...)
        end
      RUBY

      a.new.delegate(1, b: 2).should == [[1], {b: 2}]
    end

    it "delegates block" do
      a = Class.new(DelegationSpecs::Target)
      a.class_eval(<<-RUBY)
        def delegate_block(...)
          target_block(...)
        end
      RUBY

      a.new.delegate_block(1, b: 2) { |x| x }.should == [{b: 2}, [1]]
    end

    it "parses as open endless Range when brackets are ommitted" do
      a = Class.new(DelegationSpecs::Target)
      suppress_warning do
        a.class_eval(<<-RUBY)
          def delegate(...)
            target ...
          end
         RUBY
       end

       a.new.delegate(1, b: 2).should == Range.new([[], {}], nil, true)
    end
  end
end
