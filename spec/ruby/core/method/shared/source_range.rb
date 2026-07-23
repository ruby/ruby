require_relative '../../../fixtures/source_range_helpers'

describe :method_source_range, shared: true do
  it "sets absolute_path to the real path of the source file" do
    def location
    end
    method = @object.call(method(:location))
    method.source_range.absolute_path.should == File.realpath(__FILE__)
  end

  it "sets path to the source location path" do
    def location
    end
    method = @object.call(method(:location))
    method.source_range.path.should == __FILE__
  end

  it "works for singleton methods" do
    check_source_range <<-RUBY
    $def self.location
      :location
    end$

    method(:location)
    RUBY
  end

  it "works for multi-line methods" do
    check_source_range <<-RUBY
    $def multiline
      1
      2
    end$

    method(:multiline)
    RUBY
  end

  it "works for UTF-8 method names and returns byte columns" do
    check_source_range <<-RUBY
    klass = Class.new do
      $def été; 42; end$
    end

    klass.new.method(:été)
    RUBY
  end

  it "works for inline methods" do
    check_source_range <<-RUBY
    klass = Class.new do
      $def inline = 42$
    end

    klass.new.method(:inline)
    RUBY
  end

  it "does not cover a heredoc spanning beyond an inline method" do
    check_source_range <<-RUBY
    $def inline_heredoc = <<~HEREDOC$
      heredoc
    HEREDOC

    method(:inline_heredoc)
    RUBY
  end

  it "does not cover a heredoc spanning beyond a regular method" do
    check_source_range <<-RUBY
    $def heredoc; <<~HEREDOC; end$;
      heredoc
    HEREDOC

    method(:heredoc)
    RUBY
  end

  it "works for methods defined with define_method" do
    check_source_range <<-RUBY
    klass = Class.new do
      define_method(:define_method_method) ${ 42 }$
    end

    klass.new.method(:define_method_method)
    RUBY
  end

  it "returns the same range for an unbound method as the method reports" do
    def my_method_source_range
      true
    end

    method = method(:my_method_source_range)
    unbound = method.unbind

    source_range_values(unbound.source_range).should == source_range_values(method.source_range)
    unbound.source_range.path.should == method.source_range.path
    unbound.source_range.absolute_path.should == method.source_range.absolute_path
  end

  it "returns nil for core methods" do
    method = @object.call("".method(:length))

    method.source_range.should == nil
  end

  it "sets path when absolute_path is nil" do
    eval('def m; end', nil, "foo")
    method = @object.call(method(:m))
    range = method.source_range

    range.path.should == "foo"
    range.absolute_path.should == nil
  end

  it "sets #absolute_path to nil even if an absolute path is given to eval" do
    eval('def m; end', nil, "/foo")
    method = @object.call(method(:m))
    range = method.source_range

    range.path.should == "/foo"
    range.absolute_path.should == nil
  end

  it "considers eval's start line" do
    eval('def m; end', nil, "foo", 100)
    method = @object.call(method(:m))
    range = method.source_range

    range.start_line.should == 100
  end
end
