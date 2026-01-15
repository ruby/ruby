require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/actions/tag'
require 'mspec/runner/mspec'
require 'mspec/runner/example'
require 'mspec/runner/tag'

RSpec.describe TagAction, ".new" do
  it "creates an MatchFilter with its tag and desc arguments" do
    filter = double('action filter').as_null_object
    expect(MatchFilter).to receive(:new).with(nil, "some", "thing").and_return(filter)
    TagAction.new :add, :all, nil, nil, ["tag", "key"], ["some", "thing"]
  end
end

RSpec.describe TagAction, "#===" do
  before :each do
    allow(MSpec).to receive(:read_tags).and_return(["match"])
    @action = TagAction.new :add, :fail, nil, nil, nil, ["catch", "if you"]
  end

  it "returns true if there are no filters" do
    action = TagAction.new :add, :all, nil, nil
    expect(action.===("anything")).to eq(true)
  end

  it "returns true if the argument matches any of the descriptions" do
    expect(@action.===("catch")).to eq(true)
    expect(@action.===("if you can")).to eq(true)
  end

  it "returns false if the argument does not match any of the descriptions" do
    expect(@action.===("patch me")).to eq(false)
    expect(@action.===("if I can")).to eq(false)
  end
end

RSpec.describe TagAction, "#exception?" do
  before :each do
    @action = TagAction.new :add, :fail, nil, nil, nil, nil
  end

  it "returns false if no exception has been raised while evaluating an example" do
    expect(@action.exception?).to be_falsey
  end

  it "returns true if an exception was raised while evaluating an example" do
    @action.exception ExceptionState.new nil, nil, Exception.new("failed")
    expect(@action.exception?).to be_truthy
  end
end

RSpec.describe TagAction, "#outcome?" do
  before :each do
    allow(MSpec).to receive(:read_tags).and_return([])
    @exception = ExceptionState.new nil, nil, Exception.new("failed")
  end

  it "returns true if outcome is :fail and the spec fails" do
    action = TagAction.new :add, :fail, nil, nil, nil, nil
    action.exception @exception
    expect(action.outcome?).to eq(true)
  end

  it "returns false if the outcome is :fail and the spec passes" do
    action = TagAction.new :add, :fail, nil, nil, nil, nil
    expect(action.outcome?).to eq(false)
  end

  it "returns true if the outcome is :pass and the spec passes" do
    action = TagAction.new :del, :pass, nil, nil, nil, nil
    expect(action.outcome?).to eq(true)
  end

  it "returns false if the outcome is :pass and the spec fails" do
    action = TagAction.new :del, :pass, nil, nil, nil, nil
    action.exception @exception
    expect(action.outcome?).to eq(false)
  end

  it "returns true if the outcome is :all" do
    action = TagAction.new :add, :all, nil, nil, nil, nil
    action.exception @exception
    expect(action.outcome?).to eq(true)
  end
end

RSpec.describe TagAction, "#before" do
  it "resets the #exception? flag to false" do
    action = TagAction.new :add, :fail, nil, nil, nil, nil
    expect(action.exception?).to be_falsey
    action.exception ExceptionState.new(nil, nil, Exception.new("Fail!"))
    expect(action.exception?).to be_truthy
    action.before(ExampleState.new(ContextState.new("describe"), "it"))
    expect(action.exception?).to be_falsey
  end
end

RSpec.describe TagAction, "#exception" do
  it "sets the #exception? flag" do
    action = TagAction.new :add, :fail, nil, nil, nil, nil
    expect(action.exception?).to be_falsey
    action.exception ExceptionState.new(nil, nil, Exception.new("Fail!"))
    expect(action.exception?).to be_truthy
  end
end

RSpec.describe TagAction, "#after when action is :add" do
  before :each do
    allow(MSpec).to receive(:read_tags).and_return([])
    context = ContextState.new "Catch#me"
    @state = ExampleState.new context, "if you can"
    @tag = SpecTag.new "tag(comment):Catch#me if you can"
    allow(SpecTag).to receive(:new).and_return(@tag)
    @exception = ExceptionState.new nil, nil, Exception.new("failed")
  end

  it "does not write a tag if the description does not match" do
    expect(MSpec).not_to receive(:write_tag)
    action = TagAction.new :add, :all, "tag", "comment", nil, "match"
    action.after @state
  end

  it "does not write a tag if outcome is :fail and the spec passed" do
    expect(MSpec).not_to receive(:write_tag)
    action = TagAction.new :add, :fail, "tag", "comment", nil, "can"
    action.after @state
  end

  it "writes a tag if the outcome is :fail and the spec failed" do
    expect(MSpec).to receive(:write_tag).with(@tag)
    action = TagAction.new :add, :fail, "tag", "comment", nil, "can"
    action.exception @exception
    action.after @state
  end

  it "does not write a tag if outcome is :pass and the spec failed" do
    expect(MSpec).not_to receive(:write_tag)
    action = TagAction.new :add, :pass, "tag", "comment", nil, "can"
    action.exception @exception
    action.after @state
  end

  it "writes a tag if the outcome is :pass and the spec passed" do
    expect(MSpec).to receive(:write_tag).with(@tag)
    action = TagAction.new :add, :pass, "tag", "comment", nil, "can"
    action.after @state
  end

  it "writes a tag if the outcome is :all" do
    expect(MSpec).to receive(:write_tag).with(@tag)
    action = TagAction.new :add, :all, "tag", "comment", nil, "can"
    action.after @state
  end
end

RSpec.describe TagAction, "#after when action is :del" do
  before :each do
    allow(MSpec).to receive(:read_tags).and_return([])
    context = ContextState.new "Catch#me"
    @state = ExampleState.new context, "if you can"
    @tag = SpecTag.new "tag(comment):Catch#me if you can"
    allow(SpecTag).to receive(:new).and_return(@tag)
    @exception = ExceptionState.new nil, nil, Exception.new("failed")
  end

  it "does not delete a tag if the description does not match" do
    expect(MSpec).not_to receive(:delete_tag)
    action = TagAction.new :del, :all, "tag", "comment", nil, "match"
    action.after @state
  end

  it "does not delete a tag if outcome is :fail and the spec passed" do
    expect(MSpec).not_to receive(:delete_tag)
    action = TagAction.new :del, :fail, "tag", "comment", nil, "can"
    action.after @state
  end

  it "deletes a tag if the outcome is :fail and the spec failed" do
    expect(MSpec).to receive(:delete_tag).with(@tag)
    action = TagAction.new :del, :fail, "tag", "comment", nil, "can"
    action.exception @exception
    action.after @state
  end

  it "does not delete a tag if outcome is :pass and the spec failed" do
    expect(MSpec).not_to receive(:delete_tag)
    action = TagAction.new :del, :pass, "tag", "comment", nil, "can"
    action.exception @exception
    action.after @state
  end

  it "deletes a tag if the outcome is :pass and the spec passed" do
    expect(MSpec).to receive(:delete_tag).with(@tag)
    action = TagAction.new :del, :pass, "tag", "comment", nil, "can"
    action.after @state
  end

  it "deletes a tag if the outcome is :all" do
    expect(MSpec).to receive(:delete_tag).with(@tag)
    action = TagAction.new :del, :all, "tag", "comment", nil, "can"
    action.after @state
  end
end

RSpec.describe TagAction, "#finish" do
  before :each do
    $stdout = @out = IOStub.new
    context = ContextState.new "Catch#me"
    @state = ExampleState.new context, "if you can"
    allow(MSpec).to receive(:write_tag).and_return(true)
    allow(MSpec).to receive(:delete_tag).and_return(true)
  end

  after :each do
    $stdout = STDOUT
  end

  it "reports no specs tagged if none where tagged" do
    action = TagAction.new :add, :fail, "tag", "comment", nil, "can"
    allow(action).to receive(:outcome?).and_return(false)
    action.after @state
    action.finish
    expect(@out).to eq("\nTagAction: no specs were tagged with 'tag'\n")
  end

  it "reports no specs tagged if none where tagged" do
    action = TagAction.new :del, :fail, "tag", "comment", nil, "can"
    allow(action).to receive(:outcome?).and_return(false)
    action.after @state
    action.finish
    expect(@out).to eq("\nTagAction: no tags 'tag' were deleted\n")
  end

  it "reports the spec descriptions that were tagged" do
    action = TagAction.new :add, :fail, "tag", "comment", nil, "can"
    allow(action).to receive(:outcome?).and_return(true)
    action.after @state
    action.finish
    expect(@out).to eq(%[
TagAction: specs tagged with 'tag':

Catch#me if you can
])
  end

  it "reports the spec descriptions for the tags that were deleted" do
    action = TagAction.new :del, :fail, "tag", "comment", nil, "can"
    allow(action).to receive(:outcome?).and_return(true)
    action.after @state
    action.finish
    expect(@out).to eq(%[
TagAction: tag 'tag' deleted for specs:

Catch#me if you can
])
  end
end

RSpec.describe TagAction, "#register" do
  before :each do
    allow(MSpec).to receive(:register)
    allow(MSpec).to receive(:read_tags).and_return([])
    @action = TagAction.new :add, :all, nil, nil, nil, nil
  end

  it "registers itself with MSpec for the :before event" do
    expect(MSpec).to receive(:register).with(:before, @action)
    @action.register
  end

  it "registers itself with MSpec for the :after event" do
    expect(MSpec).to receive(:register).with(:after, @action)
    @action.register
  end

  it "registers itself with MSpec for the :exception event" do
    expect(MSpec).to receive(:register).with(:exception, @action)
    @action.register
  end

  it "registers itself with MSpec for the :finish event" do
    expect(MSpec).to receive(:register).with(:finish, @action)
    @action.register
  end
end

RSpec.describe TagAction, "#unregister" do
  before :each do
    allow(MSpec).to receive(:unregister)
    allow(MSpec).to receive(:read_tags).and_return([])
    @action = TagAction.new :add, :all, nil, nil, nil, nil
  end

  it "unregisters itself with MSpec for the :before event" do
    expect(MSpec).to receive(:unregister).with(:before, @action)
    @action.unregister
  end

  it "unregisters itself with MSpec for the :after event" do
    expect(MSpec).to receive(:unregister).with(:after, @action)
    @action.unregister
  end

  it "unregisters itself with MSpec for the :exception event" do
    expect(MSpec).to receive(:unregister).with(:exception, @action)
    @action.unregister
  end

  it "unregisters itself with MSpec for the :finish event" do
    expect(MSpec).to receive(:unregister).with(:finish, @action)
    @action.unregister
  end
end
