require_relative '../../spec_helper'

describe "Module#deprecate_constant" do
  before :each do
    @module = Module.new
    @value = :value
    @module::PUBLIC1 = @value
    @module::PUBLIC2 = @value
    @module::PRIVATE = @value
    @module.private_constant :PRIVATE
    @module.deprecate_constant :PRIVATE
  end

  describe "when accessing the deprecated module" do
    it "passes the accessing" do
      @module.deprecate_constant :PUBLIC1

      value = nil
      -> {
        value = @module::PUBLIC1
      }.should complain(/warning: constant .+::PUBLIC1 is deprecated/)
      value.should equal(@value)

      -> { @module::PRIVATE }.should raise_error(NameError)
    end

    it "warns with a message" do
      @module.deprecate_constant :PUBLIC1

      -> { @module::PUBLIC1 }.should complain(/warning: constant .+::PUBLIC1 is deprecated/)
      -> { @module.const_get :PRIVATE }.should complain(/warning: constant .+::PRIVATE is deprecated/)
    end

    ruby_version_is '2.7' do
      it "does not warn if Warning[:deprecated] is false" do
        @module.deprecate_constant :PUBLIC1

        deprecated = Warning[:deprecated]
        begin
          Warning[:deprecated] = false
          -> { @module::PUBLIC1 }.should_not complain
        ensure
          Warning[:deprecated] = deprecated
        end
      end
    end
  end

  it "accepts multiple symbols and strings as constant names" do
    @module.deprecate_constant "PUBLIC1", :PUBLIC2

    -> { @module::PUBLIC1 }.should complain(/warning: constant .+::PUBLIC1 is deprecated/)
    -> { @module::PUBLIC2 }.should complain(/warning: constant .+::PUBLIC2 is deprecated/)
  end

  it "returns self" do
    @module.deprecate_constant(:PUBLIC1).should equal(@module)
  end

  it "raises a NameError when given an undefined name" do
    -> { @module.deprecate_constant :UNDEFINED }.should raise_error(NameError)
  end
end
