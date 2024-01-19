require_relative '../../spec_helper'

ruby_version_is ""..."3.4" do
  require_relative 'fixtures/classes'

  describe "Observer#notify_observers" do

    before :each do
      @observable = ObservableSpecs.new
      @observer = ObserverCallbackSpecs.new
      @observable.add_observer(@observer)
    end

    it "must call changed before notifying observers" do
      @observer.value.should == nil
      @observable.notify_observers("test")
      @observer.value.should == nil
    end

    it "verifies observer responds to update" do
      -> {
        @observable.add_observer(@observable)
      }.should raise_error(NoMethodError)
    end

    it "receives the callback" do
      @observer.value.should == nil
      @observable.changed
      @observable.notify_observers("test")
      @observer.value.should == "test"
    end

  end
end
