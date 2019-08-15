require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# FIXME: These methods exist only when the -n or -p option is passed to
# ruby, but we currently don't have a way of specifying that.
ruby_version_is ""..."1.9" do
  describe "Kernel#sub" do
    it "is a private method" do
      Kernel.should have_private_instance_method(:sub)
    end
  end

  describe "Kernel#sub!" do
    it "is a private method" do
      Kernel.should have_private_instance_method(:sub!)
    end
  end

  describe "Kernel.sub" do
    it "needs to be reviewed for spec completeness"
  end

  describe "Kernel.sub!" do
    it "needs to be reviewed for spec completeness"
  end
end
