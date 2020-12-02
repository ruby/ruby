ruby_version_is ""..."3.0" do
  require_relative '../../spec_helper'
  require_relative 'fixtures/classes'

  describe "Time#succ" do
    it "returns a new time one second later than time" do
      suppress_warning {
        @result = Time.at(100).succ
      }

      @result.should == Time.at(101)
    end

    it "returns a new instance" do
      time = Time.at(100)

      suppress_warning {
        @result = time.succ
      }

      @result.should_not equal time
    end

    it "is obsolete" do
      -> {
        Time.at(100).succ
      }.should complain(/Time#succ is obsolete/)
    end

    ruby_version_is "2.6" do
      context "zone is a timezone object" do
        it "preserves time zone" do
          zone = TimeSpecs::Timezone.new(offset: (5*3600+30*60))
          time = Time.new(2012, 1, 1, 12, 0, 0, zone) - 1

          time.zone.should == zone
        end
      end
    end
  end
end
