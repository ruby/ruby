require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Observer#delete_observers" do
  before :each do
    @observable = ObservableSpecs.new
    @observer = ObserverCallbackSpecs.new
  end

  it "deletes the observers" do
    @observable.add_observer(@observer)
    @observable.delete_observers

    @observable.changed
    @observable.notify_observers("test")
    @observer.value.should == nil
  end

end
