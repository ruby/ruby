# -*- encoding: us-ascii -*-

describe :set_visibility, shared: true do
  it "is a private method" do
    Module.private_instance_methods(false).should.include?(@method)
  end

  describe "with argument" do
    describe "one or more arguments" do
      it "sets visibility of given method names" do
        visibility = @method
        old_visibility = [:protected, :private].find {|vis| vis != visibility }

        mod = Module.new {
          send old_visibility
          def test1() end
          def test2() end
          send visibility, :test1, :test2
        }
        mod.send(:"#{visibility}_instance_methods", false).should.include?(:test1)
        mod.send(:"#{visibility}_instance_methods", false).should.include?(:test2)
      end
    end

    describe "array as a single argument" do
      it "sets visibility of given method names" do
        visibility = @method
        old_visibility = [:protected, :private].find {|vis| vis != visibility }

        mod = Module.new {
          send old_visibility
          def test1() end
          def test2() end
          send visibility, [:test1, :test2]
        }
        mod.send(:"#{visibility}_instance_methods", false).should.include?(:test1)
        mod.send(:"#{visibility}_instance_methods", false).should.include?(:test2)
      end
    end

    it "does not clone method from the ancestor when setting to the same visibility in a child" do
      visibility = @method
      parent = Module.new {
        def test_method; end
        send(visibility, :test_method)
      }

      child = Module.new {
        include parent
        send(visibility, :test_method)
      }

      child.send(:"#{visibility}_instance_methods", false).should_not.include?(:test_method)
    end
  end

  describe "without arguments" do
    it "sets visibility to following method definitions" do
      visibility = @method
      mod = Module.new {
        send visibility

        def test1() end
        def test2() end
      }

      mod.send(:"#{@method}_instance_methods", false).should.include?(:test1)
      mod.send(:"#{@method}_instance_methods", false).should.include?(:test2)
    end

    it "stops setting visibility if the body encounters other visibility setters without arguments" do
      visibility = @method
      new_visibility = nil
      mod = Module.new {
        send visibility
        new_visibility = [:protected, :private].find {|vis| vis != visibility }
        send new_visibility
        def test1() end
      }

      mod.send(:"#{new_visibility}_instance_methods", false).should.include?(:test1)
    end

    it "continues setting visibility if the body encounters other visibility setters with arguments" do
      visibility = @method
      mod = Module.new {
        send visibility
        def test1() end
        send([:protected, :private].find {|vis| vis != visibility }, :test1)
        def test2() end
      }

      mod.send(:"#{@method}_instance_methods", false).should.include?(:test2)
    end

    it "does not affect module_evaled method definitions when itself is outside the eval" do
      visibility = @method
      mod = Module.new {
        send visibility

        module_eval { def test1() end }
        module_eval " def test2() end "
      }

      mod.public_instance_methods(false).should.include?(:test1)
      mod.public_instance_methods(false).should.include?(:test2)
    end

    it "does not affect outside method definitions when itself is inside a module_eval" do
      visibility = @method
      mod = Module.new {
        module_eval { send visibility }

        def test1() end
      }

      mod.public_instance_methods(false).should.include?(:test1)
    end

    it "affects normally if itself and method definitions are inside a module_eval" do
      visibility = @method
      mod = Module.new {
        module_eval {
          send visibility

          def test1() end
        }
      }

      mod.send(:"#{@method}_instance_methods", false).should.include?(:test1)
    end

    it "does not affect method definitions when itself is inside an eval and method definitions are outside" do
      visibility = @method
      initialized_visibility = [:public, :protected, :private].find {|sym| sym != visibility }
      mod = Module.new {
        send initialized_visibility
        eval visibility.to_s

        def test1() end
      }

      mod.send(:"#{initialized_visibility}_instance_methods", false).should.include?(:test1)
    end

    it "affects evaled method definitions when itself is outside the eval" do
      visibility = @method
      mod = Module.new {
        send visibility

        eval "def test1() end"
      }

      mod.send(:"#{@method}_instance_methods", false).should.include?(:test1)
    end

    it "affects normally if itself and following method definitions are inside a eval" do
      visibility = @method
      mod = Module.new {
        eval <<-CODE
          #{visibility}

          def test1() end
        CODE
      }

      mod.send(:"#{@method}_instance_methods", false).should.include?(:test1)
    end

    describe "within a closure" do
      it "sets the visibility outside the closure" do
        visibility = @method
        mod = Module.new {
          1.times {
            send visibility
          }
          def test1() end
        }

        mod.send(:"#{@method}_instance_methods", false).should.include?(:test1)
      end
    end
  end
end
