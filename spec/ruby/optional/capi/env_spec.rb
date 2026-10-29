require_relative 'spec_helper'

platform_is_not :windows do
  load_extension("env")

  # ENV is a core library object rather than part of the C API, but its contract
  # with native extensions is: the process environment is shared, so a variable
  # that an extension sets with setenv() must be visible to ENV, and one that ENV
  # sets must be visible to getenv(). Testing that requires calling the C library
  # directly, so the spec lives with the other specs that need a native
  # extension, and runs on any implementation to check the two agree.
  describe "ENV" do
    before :each do
      @f = CApiEnvSpecs.new
      @name = "CAPI_ENV_SPEC"
    end

    after :each do
      @f.unsetenv(@name)
    end

    describe "when a variable is set by a native extension" do
      it "is returned by ENV#[]" do
        @f.setenv(@name, "native")
        ENV[@name].should == "native"
      end

      it "is returned by ENV#fetch" do
        @f.setenv(@name, "native")
        ENV.fetch(@name).should == "native"
      end

      it "is reported by ENV#key?" do
        @f.setenv(@name, "native")
        ENV.key?(@name).should == true
      end

      it "is enumerated by ENV#keys" do
        @f.setenv(@name, "native")
        ENV.keys.should.include?(@name)
      end

      it "is enumerated by ENV#each" do
        @f.setenv(@name, "native")
        ENV.to_hash[@name].should == "native"
      end

      it "is counted by ENV#size" do
        before_size = ENV.size
        @f.setenv(@name, "native")
        ENV.size.should == before_size + 1
      end
    end

    describe "when a variable is changed by a native extension" do
      it "returns the new value from ENV#[]" do
        ENV[@name] = "ruby"
        @f.setenv(@name, "native")
        ENV[@name].should == "native"
      end

      it "returns the new value even after ENV has already read the old one" do
        ENV[@name] = "ruby"
        ENV[@name].should == "ruby"
        @f.setenv(@name, "native")
        ENV[@name].should == "native"
      end
    end

    describe "when a variable is removed by a native extension" do
      it "returns nil from ENV#[]" do
        ENV[@name] = "ruby"
        @f.unsetenv(@name)
        ENV[@name].should == nil
      end

      it "is not reported by ENV#key?" do
        ENV[@name] = "ruby"
        @f.unsetenv(@name)
        ENV.key?(@name).should == false
      end

      it "is not enumerated by ENV#keys" do
        ENV[@name] = "ruby"
        @f.unsetenv(@name)
        ENV.keys.should_not.include?(@name)
      end
    end

    describe "when a variable is set by Ruby" do
      it "is visible to getenv() in a native extension" do
        ENV[@name] = "ruby"
        @f.getenv(@name).should == "ruby"
      end

      it "is no longer visible to getenv() once deleted" do
        ENV[@name] = "ruby"
        ENV.delete(@name)
        @f.getenv(@name).should == nil
      end

      it "is visible to getenv() with the value it was last given" do
        ENV[@name] = "one"
        ENV[@name] = "two"
        @f.getenv(@name).should == "two"
      end
    end

    it "keeps #size consistent with the keys it enumerates when native code adds a variable" do
      @f.setenv(@name, "native")
      ENV.size.should == ENV.keys.size
    end
  end
end
