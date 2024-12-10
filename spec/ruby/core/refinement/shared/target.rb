describe :refinement_target, shared: true do
  it "returns the class refined by the receiver" do
    refinement_int = nil

    Module.new do
      refine Integer do
        refinement_int = self
      end
    end

    refinement_int.send(@method).should == Integer
  end
end
