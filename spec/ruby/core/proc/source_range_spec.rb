require_relative '../../spec_helper'
require_relative '../../fixtures/source_range_helpers'

ruby_version_is "4.1" do
  describe "Proc#source_range" do
    it "sets absolute_path to the real path of the source file" do
      my_proc = proc {}
      my_proc.source_range.absolute_path.should == File.realpath(__FILE__)
    end

    it "sets path to the source location path" do
      my_proc = proc {}
      my_proc.source_range.path.should == __FILE__
    end

    it "works for proc {}" do
      check_source_range <<-RUBY
      proc ${}$
      RUBY
    end

    it "works for Proc.new {}" do
      check_source_range <<-RUBY
      Proc.new ${}$
      RUBY
    end

    it "works for lambda {}" do
      check_source_range <<-RUBY
      lambda ${}$
      RUBY
    end

    it "works for -> {}" do
      check_source_range <<-RUBY
      $-> {}$
      RUBY
    end

    it "works with multibyte characters and return byte columns" do
      check_source_range <<-RUBY
      $-> (il, était, un) { été }$
      RUBY
    end

    it "works for multi-line procs" do
      check_source_range <<-RUBY
      proc $do
        'a'.upcase
        1 + 22
      end$
      RUBY
    end

    it "works for returned blocks" do
      check_source_range <<-RUBY
      def return_block(&block)
        block
      end

      return_block ${ 42 }$
      RUBY
    end

    it "works for blocks passed to calls with receivers" do
      check_source_range <<-RUBY
      def block_receiver
        obj = Object.new
        def obj.foo(&block)
          block
        end
        obj
      end

      block_receiver.foo ${ 42 }$
      RUBY
    end

    it "uses the '}' as the end bound for a Proc with a heredoc inside" do
      check_source_range <<-RUBY
      proc ${ <<~END }$
        heredoc
      END
      RUBY
    end

    it "works for for-loop body procs" do
      check_source_range <<-RUBY
      iter = Object.new
      def iter.each(&block)
        block.call(block)
      end

      $for pr in iter
        42
      end$

      pr
      RUBY
    end

    it "works for define_method & to_proc" do
      check_source_range <<-RUBY
      self.singleton_class.define_method :foo $do
        1 + 2
      end$

      method(:foo).to_proc
      RUBY
    end

    it "returns the same range for a proc-ified method as the method reports" do
      def my_proc
        proc { true }
      end

      meth = method(:my_proc)
      proc = meth.to_proc

      source_range_values(proc.source_range).should == source_range_values(meth.source_range)
      proc.source_range.path.should == meth.source_range.path
      proc.source_range.absolute_path.should == meth.source_range.absolute_path
    end

    it "returns nil for a core method that has been proc-ified" do
      [].method(:<<).to_proc.source_range.should == nil
    end

    it "sets #path when #absolute_path is nil" do
      range = eval('-> { 1 }', nil, "foo").source_range
      range.path.should == "foo"
      range.absolute_path.should == nil
    end

    it "sets #absolute_path to nil even if an absolute path is given to eval" do
      range = eval('-> { 1 }', nil, "/foo").source_range
      range.path.should == "/foo"
      range.absolute_path.should == nil
    end

    it "considers eval's start line" do
      range = eval('-> { 1 }', nil, "foo", 100).source_range
      range.start_line.should == 100
    end
  end
end
