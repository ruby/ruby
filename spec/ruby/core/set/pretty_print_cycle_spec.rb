require_relative '../../spec_helper'

describe "Set#pretty_print_cycle" do
  it "passes the 'pretty print' representation of a self-referencing Set to the pretty print writer" do
    pp = mock("PrettyPrint")
    ruby_version_is(""..."4.0") do
      pp.should_receive(:text).with("#<Set: {...}>")
    end
    ruby_version_is("4.0") do
      pp.should_receive(:text).with("Set[...]")
    end
    Set[1, 2, 3].pretty_print_cycle(pp)
  end
end
