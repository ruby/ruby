require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Observer#add_observer" do

  before :each do
    @observable = ObservableSpecs.new
    @observer = ObserverCallbackSpecs.new
  end

  it "adds the observer" do
    @observer.value.should == nil
    @observable.changed
    @observable.notify_observers("test")
    @observer.value.should == nil

    @observable.add_observer(@observer)
    @observable.changed
    @observable.notify_observers("test2")
    @observer.value.should == "test2"
  end

end
