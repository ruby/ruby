require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/actions/tag'
require 'mspec/runner/mspec'
require 'mspec/runner/example'
require 'mspec/runner/tag'

describe TagAction, ".new" do
  it "creates an MatchFilter with its tag and desc arguments" do
    filter = double('action filter').as_null_object
    MatchFilter.should_receive(:new).with(nil, "some", "thing").and_return(filter)
    TagAction.new :add, :all, nil, nil, ["tag", "key"], ["some", "thing"]
  end
end

describe TagAction, "#===" do
  before :each do
    MSpec.stub(:read_tags).and_return(["match"])
    @action = TagAction.new :add, :fail, nil, nil, nil, ["catch", "if you"]
  end

  it "returns true if there are no filters" do
    action = TagAction.new :add, :all, nil, nil
    action.===("anything").should == true
  end

  it "returns true if the argument matches any of the descriptions" do
    @action.===("catch").should == true
    @action.===("if you can").should == true
  end

  it "returns false if the argument does not match any of the descriptions" do
    @action.===("patch me").should == false
    @action.===("if I can").should == false
  end
end

describe TagAction, "#exception?" do
  before :each do
    @action = TagAction.new :add, :fail, nil, nil, nil, nil
  end

  it "returns false if no exception has been raised while evaluating an example" do
    @action.exception?.should be_false
  end

  it "returns true if an exception was raised while evaluating an example" do
    @action.exception ExceptionState.new nil, nil, Exception.new("failed")
    @action.exception?.should be_true
  end
end

describe TagAction, "#outcome?" do
  before :each do
    MSpec.stub(:read_tags).and_return([])
    @exception = ExceptionState.new nil, nil, Exception.new("failed")
  end

  it "returns true if outcome is :fail and the spec fails" do
    action = TagAction.new :add, :fail, nil, nil, nil, nil
    action.exception @exception
    action.outcome?.should == true
  end

  it "returns false if the outcome is :fail and the spec passes" do
    action = TagAction.new :add, :fail, nil, nil, nil, nil
    action.outcome?.should == false
  end

  it "returns true if the outcome is :pass and the spec passes" do
    action = TagAction.new :del, :pass, nil, nil, nil, nil
    action.outcome?.should == true
  end

  it "returns false if the outcome is :pass and the spec fails" do
    action = TagAction.new :del, :pass, nil, nil, nil, nil
    action.exception @exception
    action.outcome?.should == false
  end

  it "returns true if the outcome is :all" do
    action = TagAction.new :add, :all, nil, nil, nil, nil
    action.exception @exception
    action.outcome?.should == true
  end
end

describe TagAction, "#before" do
  it "resets the #exception? flag to false" do
    action = TagAction.new :add, :fail, nil, nil, nil, nil
    action.exception?.should be_false
    action.exception ExceptionState.new(nil, nil, Exception.new("Fail!"))
    action.exception?.should be_true
    action.before(ExampleState.new(ContextState.new("describe"), "it"))
    action.exception?.should be_false
  end
end

describe TagAction, "#exception" do
  it "sets the #exception? flag" do
    action = TagAction.new :add, :fail, nil, nil, nil, nil
    action.exception?.should be_false
    action.exception ExceptionState.new(nil, nil, Exception.new("Fail!"))
    action.exception?.should be_true
  end
end

describe TagAction, "#after when action is :add" do
  before :each do
    MSpec.stub(:read_tags).and_return([])
    context = ContextState.new "Catch#me"
    @state = ExampleState.new context, "if you can"
    @tag = SpecTag.new "tag(comment):Catch#me if you can"
    SpecTag.stub(:new).and_return(@tag)
    @exception = ExceptionState.new nil, nil, Exception.new("failed")
  end

  it "does not write a tag if the description does not match" do
    MSpec.should_not_receive(:write_tag)
    action = TagAction.new :add, :all, "tag", "comment", nil, "match"
    action.after @state
  end

  it "does not write a tag if outcome is :fail and the spec passed" do
    MSpec.should_not_receive(:write_tag)
    action = TagAction.new :add, :fail, "tag", "comment", nil, "can"
    action.after @state
  end

  it "writes a tag if the outcome is :fail and the spec failed" do
    MSpec.should_receive(:write_tag).with(@tag)
    action = TagAction.new :add, :fail, "tag", "comment", nil, "can"
    action.exception @exception
    action.after @state
  end

  it "does not write a tag if outcome is :pass and the spec failed" do
    MSpec.should_not_receive(:write_tag)
    action = TagAction.new :add, :pass, "tag", "comment", nil, "can"
    action.exception @exception
    action.after @state
  end

  it "writes a tag if the outcome is :pass and the spec passed" do
    MSpec.should_receive(:write_tag).with(@tag)
    action = TagAction.new :add, :pass, "tag", "comment", nil, "can"
    action.after @state
  end

  it "writes a tag if the outcome is :all" do
    MSpec.should_receive(:write_tag).with(@tag)
    action = TagAction.new :add, :all, "tag", "comment", nil, "can"
    action.after @state
  end
end

describe TagAction, "#after when action is :del" do
  before :each do
    MSpec.stub(:read_tags).and_return([])
    context = ContextState.new "Catch#me"
    @state = ExampleState.new context, "if you can"
    @tag = SpecTag.new "tag(comment):Catch#me if you can"
    SpecTag.stub(:new).and_return(@tag)
    @exception = ExceptionState.new nil, nil, Exception.new("failed")
  end

  it "does not delete a tag if the description does not match" do
    MSpec.should_not_receive(:delete_tag)
    action = TagAction.new :del, :all, "tag", "comment", nil, "match"
    action.after @state
  end

  it "does not delete a tag if outcome is :fail and the spec passed" do
    MSpec.should_not_receive(:delete_tag)
    action = TagAction.new :del, :fail, "tag", "comment", nil, "can"
    action.after @state
  end

  it "deletes a tag if the outcome is :fail and the spec failed" do
    MSpec.should_receive(:delete_tag).with(@tag)
    action = TagAction.new :del, :fail, "tag", "comment", nil, "can"
    action.exception @exception
    action.after @state
  end

  it "does not delete a tag if outcome is :pass and the spec failed" do
    MSpec.should_not_receive(:delete_tag)
    action = TagAction.new :del, :pass, "tag", "comment", nil, "can"
    action.exception @exception
    action.after @state
  end

  it "deletes a tag if the outcome is :pass and the spec passed" do
    MSpec.should_receive(:delete_tag).with(@tag)
    action = TagAction.new :del, :pass, "tag", "comment", nil, "can"
    action.after @state
  end

  it "deletes a tag if the outcome is :all" do
    MSpec.should_receive(:delete_tag).with(@tag)
    action = TagAction.new :del, :all, "tag", "comment", nil, "can"
    action.after @state
  end
end

describe TagAction, "#finish" do
  before :each do
    $stdout = @out = IOStub.new
    context = ContextState.new "Catch#me"
    @state = ExampleState.new context, "if you can"
    MSpec.stub(:write_tag).and_return(true)
    MSpec.stub(:delete_tag).and_return(true)
  end

  after :each do
    $stdout = STDOUT
  end

  it "reports no specs tagged if none where tagged" do
    action = TagAction.new :add, :fail, "tag", "comment", nil, "can"
    action.stub(:outcome?).and_return(false)
    action.after @state
    action.finish
    @out.should == "\nTagAction: no specs were tagged with 'tag'\n"
  end

  it "reports no specs tagged if none where tagged" do
    action = TagAction.new :del, :fail, "tag", "comment", nil, "can"
    action.stub(:outcome?).and_return(false)
    action.after @state
    action.finish
    @out.should == "\nTagAction: no tags 'tag' were deleted\n"
  end

  it "reports the spec descriptions that were tagged" do
    action = TagAction.new :add, :fail, "tag", "comment", nil, "can"
    action.stub(:outcome?).and_return(true)
    action.after @state
    action.finish
    @out.should ==
%[
TagAction: specs tagged with 'tag':

Catch#me if you can
]
  end

  it "reports the spec descriptions for the tags that were deleted" do
    action = TagAction.new :del, :fail, "tag", "comment", nil, "can"
    action.stub(:outcome?).and_return(true)
    action.after @state
    action.finish
    @out.should ==
%[
TagAction: tag 'tag' deleted for specs:

Catch#me if you can
]
  end
end

describe TagAction, "#register" do
  before :each do
    MSpec.stub(:register)
    MSpec.stub(:read_tags).and_return([])
    @action = TagAction.new :add, :all, nil, nil, nil, nil
  end

  it "registers itself with MSpec for the :before event" do
    MSpec.should_receive(:register).with(:before, @action)
    @action.register
  end

  it "registers itself with MSpec for the :after event" do
    MSpec.should_receive(:register).with(:after, @action)
    @action.register
  end

  it "registers itself with MSpec for the :exception event" do
    MSpec.should_receive(:register).with(:exception, @action)
    @action.register
  end

  it "registers itself with MSpec for the :finish event" do
    MSpec.should_receive(:register).with(:finish, @action)
    @action.register
  end
end

describe TagAction, "#unregister" do
  before :each do
    MSpec.stub(:unregister)
    MSpec.stub(:read_tags).and_return([])
    @action = TagAction.new :add, :all, nil, nil, nil, nil
  end

  it "unregisters itself with MSpec for the :before event" do
    MSpec.should_receive(:unregister).with(:before, @action)
    @action.unregister
  end

  it "unregisters itself with MSpec for the :after event" do
    MSpec.should_receive(:unregister).with(:after, @action)
    @action.unregister
  end

  it "unregisters itself with MSpec for the :exception event" do
    MSpec.should_receive(:unregister).with(:exception, @action)
    @action.unregister
  end

  it "unregisters itself with MSpec for the :finish event" do
    MSpec.should_receive(:unregister).with(:finish, @action)
    @action.unregister
  end
end
