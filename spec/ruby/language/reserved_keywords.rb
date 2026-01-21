require_relative '../spec_helper'

describe "Ruby's reserved keywords" do
  # Copied from https://github.com/ruby/ruby/blob/master/defs/keywords
  keywords = %w[
    alias
    and
    begin
    BEGIN
    break
    case
    class
    def
    defined?
    do
    else
    elsif
    end
    END
    ensure
    false
    for
    if
    in
    module
    next
    nil
    not
    or
    redo
    rescue
    retry
    return
    self
    super
    then
    true
    undef
    unless
    until
    when
    while
    yield
    __ENCODING__
    __FILE__
    __LINE__
  ]

  keywords.each do |name|
    describe "keyword '#{name}'" do
      it "can't be used as local variable name" do
        -> { eval(<<~RUBY) }.should raise_error(SyntaxError)
            #{name} = :local_variable
        RUBY
      end

      if name == "defined?"
        it "can't be used as an instance variable name" do
          -> { eval(<<~RUBY) }.should raise_error(SyntaxError)
            @#{name} = :instance_variable
          RUBY
        end

        it "can't be used as a class variable name" do
          -> { eval(<<~RUBY) }.should raise_error(SyntaxError)
            class C
              @@#{name} = :class_variable
            end
          RUBY
        end

        it "can't be used as a global variable name" do
          -> { eval(<<~RUBY) }.should raise_error(SyntaxError)
            $#{name} = :global_variable
          RUBY
        end
      else
        it "can be used as an instance variable name" do
          result = eval <<~RUBY
            @#{name} = :instance_variable
            @#{name}
          RUBY

          result.should == :instance_variable
        end

        it "can be used as a class variable name" do
          result = eval <<~RUBY
            class C
              @@#{name} = :class_variable
              @@#{name}
            end
          RUBY

          result.should == :class_variable
        end

        it "can be used as a global variable name" do
          result = eval <<~RUBY
            $#{name} = :global_variable
            $#{name}
          RUBY

          result.should == :global_variable
        end
      end

      it "can't be used as a positional parameter name" do
        -> { eval(<<~RUBY) }.should raise_error(SyntaxError)
          def x(#{name}); end
        RUBY
      end

      invalid_kw_param_names = ["BEGIN","END","defined?"]

      if invalid_kw_param_names.include?(name)
        it "can't be used a keyword parameter name" do
          -> { eval(<<~RUBY) }.should raise_error(SyntaxError)
            def m(#{name}:); end
          RUBY
        end
      else
        it "can be used a keyword parameter name" do
          result = instance_eval <<~RUBY
            def m(#{name}:)
              binding.local_variable_get(:#{name})
            end

            m(#{name}: :argument)
          RUBY

          result.should == :argument
        end
      end

      it "can be used as a method name" do
        result = instance_eval <<~RUBY
          def #{name}
            :method_return_value
          end

          send(:#{name})
        RUBY

        result.should == :method_return_value
      end
    end
  end
end
