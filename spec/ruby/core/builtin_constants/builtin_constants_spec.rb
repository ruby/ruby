require_relative '../../spec_helper'

describe "RUBY_VERSION" do
  it "is a String" do
    RUBY_VERSION.should be_kind_of(String)
  end

  it "is frozen" do
    RUBY_VERSION.should.frozen?
  end
end

describe "RUBY_PATCHLEVEL" do
  it "is an Integer" do
    RUBY_PATCHLEVEL.should be_kind_of(Integer)
  end
end

describe "RUBY_COPYRIGHT" do
  it "is a String" do
    RUBY_COPYRIGHT.should be_kind_of(String)
  end

  it "is frozen" do
    RUBY_COPYRIGHT.should.frozen?
  end
end

describe "RUBY_DESCRIPTION" do
  it "is a String" do
    RUBY_DESCRIPTION.should be_kind_of(String)
  end

  it "is frozen" do
    RUBY_DESCRIPTION.should.frozen?
  end
end

describe "RUBY_ENGINE" do
  it "is a String" do
    RUBY_ENGINE.should be_kind_of(String)
  end

  it "is frozen" do
    RUBY_ENGINE.should.frozen?
  end
end

describe "RUBY_ENGINE_VERSION" do
  it "is a String" do
    RUBY_ENGINE_VERSION.should be_kind_of(String)
  end

  it "is frozen" do
    RUBY_ENGINE_VERSION.should.frozen?
  end
end

describe "RUBY_PLATFORM" do
  it "is a String" do
    RUBY_PLATFORM.should be_kind_of(String)
  end

  it "is frozen" do
    RUBY_PLATFORM.should.frozen?
  end
end

describe "RUBY_RELEASE_DATE" do
  it "is a String" do
    RUBY_RELEASE_DATE.should be_kind_of(String)
  end

  it "is frozen" do
    RUBY_RELEASE_DATE.should.frozen?
  end
end

describe "RUBY_REVISION" do
  it "is a String" do
    RUBY_REVISION.should be_kind_of(String)
  end

  it "is frozen" do
    RUBY_REVISION.should.frozen?
  end
end

ruby_version_is "4.0" do
  context "The constant" do
    describe "Ruby" do
      it "is a Module" do
        Ruby.should.instance_of?(Module)
      end
    end

    describe "Ruby::VERSION" do
      it "is equal to RUBY_VERSION" do
        Ruby::VERSION.should equal(RUBY_VERSION)
      end
    end

    describe "RUBY::PATCHLEVEL" do
      it "is equal to RUBY_PATCHLEVEL" do
        Ruby::PATCHLEVEL.should equal(RUBY_PATCHLEVEL)
      end
    end

    describe "Ruby::COPYRIGHT" do
      it "is equal to RUBY_COPYRIGHT" do
        Ruby::COPYRIGHT.should equal(RUBY_COPYRIGHT)
      end
    end

    describe "Ruby::DESCRIPTION" do
      it "is equal to RUBY_DESCRIPTION" do
        Ruby::DESCRIPTION.should equal(RUBY_DESCRIPTION)
      end
    end

    describe "Ruby::ENGINE" do
      it "is equal to RUBY_ENGINE" do
        Ruby::ENGINE.should equal(RUBY_ENGINE)
      end
    end

    describe "Ruby::ENGINE_VERSION" do
      it "is equal to RUBY_ENGINE_VERSION" do
        Ruby::ENGINE_VERSION.should equal(RUBY_ENGINE_VERSION)
      end
    end

    describe "Ruby::PLATFORM" do
      it "is equal to RUBY_PLATFORM" do
        Ruby::PLATFORM.should equal(RUBY_PLATFORM)
      end
    end

    describe "Ruby::RELEASE_DATE" do
      it "is equal to RUBY_RELEASE_DATE" do
        Ruby::RELEASE_DATE.should equal(RUBY_RELEASE_DATE)
      end
    end

    describe "Ruby::REVISION" do
      it "is equal to RUBY_REVISION" do
        Ruby::REVISION.should equal(RUBY_REVISION)
      end
    end
  end
end
