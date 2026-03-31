# frozen_string_literal: true

RSpec.describe Bundler::Plugin::Events do
  context "plugin events" do
    before do
      @old_constants = Bundler::Plugin::Events.constants.map {|name| [name, Bundler::Plugin::Events.const_get(name)] }
      Bundler::Plugin::Events.send :reset
    end

    after do
      Bundler::Plugin::Events.send(:reset)
      Hash[@old_constants].each do |name, value|
        Bundler::Plugin::Events.send(:define, name, value)
      end
    end

    describe "#define" do
      it "raises when redefining a constant" do
        Bundler::Plugin::Events.send(:define, :TEST_EVENT, "foo")

        expect do
          Bundler::Plugin::Events.send(:define, :TEST_EVENT, "bar")
        end.to raise_error(ArgumentError)
      end

      it "can define a new constant" do
        Bundler::Plugin::Events.send(:define, :NEW_CONSTANT, "value")
        expect(Bundler::Plugin::Events::NEW_CONSTANT).to eq("value")
      end
    end
  end
end
