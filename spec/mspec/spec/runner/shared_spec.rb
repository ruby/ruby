require 'spec_helper'
require 'mspec/runner/shared'
require 'mspec/runner/context'
require 'mspec/runner/example'

RSpec.describe Object, "#it_behaves_like" do
  before :each do
    ScratchPad.clear

    MSpec.setup_env

    @state = ContextState.new "Top level"
    @state.instance_variable_set :@parsed, true
    @state.singleton_class.send(:public, :it_behaves_like)

    @shared = ContextState.new :shared_spec, :shared => true
    allow(MSpec).to receive(:retrieve_shared).and_return(@shared)
  end

  it "creates @method set to the name of the aliased method" do
    @shared.it("an example") { ScratchPad.record @method }
    @state.it_behaves_like :shared_spec, :some_method
    @state.process
    expect(ScratchPad.recorded).to eq(:some_method)
  end

  it "creates @object if the passed object" do
    object = Object.new
    @shared.it("an example") { ScratchPad.record @object }
    @state.it_behaves_like :shared_spec, :some_method, object
    @state.process
    expect(ScratchPad.recorded).to eq(object)
  end

  it "creates @object if the passed false" do
    object = false
    @shared.it("an example") { ScratchPad.record @object }
    @state.it_behaves_like :shared_spec, :some_method, object
    @state.process
    expect(ScratchPad.recorded).to eq(object)
  end

  it "sends :it_should_behave_like" do
    expect(@state).to receive(:it_should_behave_like)
    @state.it_behaves_like :shared_spec, :some_method
  end

  describe "with multiple shared contexts" do
    before :each do
      @obj = Object.new
      @obj2 = Object.new

      @state2 = ContextState.new "Second top level"
      @state2.instance_variable_set :@parsed, true
      @state2.singleton_class.send(:public, :it_behaves_like)
    end

    it "ensures the shared spec state is distinct" do
      @shared.it("an example") { ScratchPad.record [@method, @object] }

      @state.it_behaves_like :shared_spec, :some_method, @obj

      @state.process
      expect(ScratchPad.recorded).to eq([:some_method, @obj])

      @state2.it_behaves_like :shared_spec, :another_method, @obj2

      @state2.process
      expect(ScratchPad.recorded).to eq([:another_method, @obj2])
    end

    it "ensures the shared spec state is distinct for nested shared specs" do
      nested = ContextState.new "nested context"
      nested.instance_variable_set :@parsed, true
      nested.parent = @shared

      nested.it("another example") { ScratchPad.record [:shared, @method, @object] }

      @state.it_behaves_like :shared_spec, :some_method, @obj

      @state.process
      expect(ScratchPad.recorded).to eq([:shared, :some_method, @obj])

      @state2.it_behaves_like :shared_spec, :another_method, @obj2

      @state2.process
      expect(ScratchPad.recorded).to eq([:shared, :another_method, @obj2])
    end
  end
end
