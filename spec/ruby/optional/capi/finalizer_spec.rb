require_relative "spec_helper"

extension_path = load_extension("finalizer")

describe "CApiFinalizerSpecs" do
  before :each do
    @s = CApiFinalizerSpecs.new
  end

  describe "rb_define_finalizer" do
    it "defines a finalizer on the object" do
      code = <<~RUBY
        require #{extension_path.dump}

        obj = Object.new
        finalizer = Proc.new { puts "finalizer run" }
        CApiFinalizerSpecs.new.rb_define_finalizer(obj, finalizer)
      RUBY

      ruby_exe(code).should == "finalizer run\n"
    end
  end

  describe "rb_undefine_finalizer" do
    ruby_bug "#20981", "3.4.0"..."3.4.2" do
      it "removes finalizers from the object" do
        code = <<~RUBY
          require #{extension_path.dump}

          obj = Object.new
          finalizer = Proc.new { puts "finalizer run" }
          ObjectSpace.define_finalizer(obj, finalizer)
          CApiFinalizerSpecs.new.rb_undefine_finalizer(obj)
        RUBY

        ruby_exe(code).should.empty?
      end
    end
  end
end
