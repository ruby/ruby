require_relative '../../spec_helper'

describe "FrozenError" do
  ruby_version_is "2.5" do
    it "is a subclass of RuntimeError" do
      RuntimeError.should be_ancestor_of(FrozenError)
    end
  end
end

describe "FrozenError.new" do
  ruby_version_is "2.7" do
    it "should take optional receiver argument" do
      o = Object.new
      FrozenError.new("msg", o).receiver.should equal(o)
    end
  end
end

describe "FrozenError#receiver" do
  ruby_version_is "2.7" do
    it "should return frozen object that modification was attempted on" do
      o = Object.new.freeze
      begin
        def o.x; end
      rescue => e
        e.should be_kind_of(FrozenError)
        e.receiver.should equal(o)
      else
        raise
      end
    end
  end
end
