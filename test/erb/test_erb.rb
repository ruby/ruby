require 'test/unit'
require 'erb'

class TestERB < Test::Unit::TestCase
  class MyError < RuntimeError ; end

  def test_without_filename
    erb = ERB.new("<% raise ::TestERB::MyError %>")
    e = assert_raise(MyError) {
      erb.result
    }
    assert_equal("(erb):1", e.backtrace[0])
  end

  def test_with_filename
    erb = ERB.new("<% raise ::TestERB::MyError %>")
    erb.filename = "test filename"
    e = assert_raise(MyError) {
      erb.result
    }
    assert_equal("test filename:1", e.backtrace[0])
  end

  def test_without_filename_with_safe_level
    erb = ERB.new("<% raise ::TestERB::MyError %>", 1)
    e = assert_raise(MyError) {
      erb.result
    }
    assert_equal("(erb):1", e.backtrace[0])
  end

  def test_with_filename_and_safe_level
    erb = ERB.new("<% raise ::TestERB::MyError %>", 1)
    erb.filename = "test filename"
    e = assert_raise(MyError) {
      erb.result
    }
    assert_equal("test filename:1", e.backtrace[0])
  end
end

class TestERBCore < Test::Unit::TestCase
  def setup
    @erb = ERB
  end

  def test_01
    _test_01(nil)
    _test_01(0)
    _test_01(1)
    _test_01(2)
    _test_01(3)
  end

  def _test_01(safe)
    erb = @erb.new("hello")
    assert_equal(erb.result, "hello")

    erb = @erb.new("hello", safe, 0)
    assert_equal(erb.result, "hello")

    erb = @erb.new("hello", safe, 1)
    assert_equal(erb.result, "hello")

    erb = @erb.new("hello", safe, 2)
    assert_equal(erb.result, "hello")

    src = <<EOS
%% hi
= hello
<% 3.times do |n| %>
% n=0
* <%= n %>
<% end %>
EOS
      
    ans = <<EOS
%% hi
= hello

% n=0
* 0

% n=0
* 1

% n=0
* 2

EOS
    erb = @erb.new(src)
    assert_equal(ans, erb.result)
    erb = @erb.new(src, safe, 0)
    assert_equal(ans, erb.result)
    erb = @erb.new(src, safe, '')
    assert_equal(ans, erb.result)

    ans = <<EOS
%% hi
= hello
% n=0
* 0% n=0
* 1% n=0
* 2
EOS
    erb = @erb.new(src, safe, 1)
    assert_equal(ans.chomp, erb.result)
    erb = @erb.new(src, safe, '>')
    assert_equal(ans.chomp, erb.result)

    ans  = <<EOS
%% hi
= hello
% n=0
* 0
% n=0
* 1
% n=0
* 2
EOS
      
    erb = @erb.new(src, safe, 2)
    assert_equal(ans, erb.result)
    erb = @erb.new(src, safe, '<>')
    assert_equal(ans, erb.result)

    ans = <<EOS
% hi
= hello

* 0

* 0

* 0

EOS
    erb = @erb.new(src, safe, '%')
    assert_equal(ans, erb.result)

    ans = <<EOS
% hi
= hello
* 0* 0* 0
EOS
    erb = @erb.new(src, safe, '%>')
    assert_equal(ans.chomp, erb.result)

    ans = <<EOS
% hi
= hello
* 0
* 0
* 0
EOS
    erb = @erb.new(src, safe, '%<>')
    assert_equal(ans, erb.result)
  end

  def test_02_safe_04
    erb = @erb.new('<%=$SAFE%>', 4)
    assert_equal(erb.result(TOPLEVEL_BINDING.taint), '4')
  end

  class Foo; end

  def test_03_def_class
    erb = @erb.new('hello')
    cls = erb.def_class
    assert_equal(Object, cls.superclass)
    assert(cls.new.respond_to?('result'))
    cls = erb.def_class(Foo)
    assert_equal(Foo, cls.superclass)
    assert(cls.new.respond_to?('result'))
    cls = erb.def_class(Object, 'erb')
    assert_equal(Object, cls.superclass)
    assert(cls.new.respond_to?('erb'))
  end

  def test_04_percent
    src = <<EOS
%n = 1
<%= n%>
EOS
    assert_equal("1\n", ERB.new(src, nil, '%').result)

    src = <<EOS
<%
%>
EOS
    ans = "\n"
    assert_equal(ans, ERB.new(src, nil, '%').result)

    src = "<%\n%>"
    # ans = "\n"
    ans = ""
    assert_equal(ans, ERB.new(src, nil, '%').result)

    src = <<EOS
<%
n = 1
%><%= n%>
EOS
    assert_equal("1\n", ERB.new(src, nil, '%').result)

    src = <<EOS
%n = 1
%% <% n = 2
n.times do |i|%>
%% %%><%%<%= i%><%
end%>
EOS
    ans = <<EOS
% 
% %%><%0
% %%><%1
EOS
    assert_equal(ans, ERB.new(src, nil, '%').result)
  end

  class Bar; end

  def test_05_def_method
    assert(! Bar.new.respond_to?('hello'))
    Bar.module_eval do
      extend ERB::DefMethod
      fname = File.join(File.dirname(File.expand_path(__FILE__)), 'hello.erb')
      def_erb_method('hello', fname)
    end
    assert(Bar.new.respond_to?('hello'))

    assert(! Bar.new.respond_to?('hello_world'))
    erb = @erb.new('hello, world')
    Bar.module_eval do
      def_erb_method('hello_world', erb)
    end
    assert(Bar.new.respond_to?('hello_world'))    
  end

  def test_06_escape
    src = <<EOS
1.<%% : <%="<%%"%>
2.%%> : <%="%%>"%>
3.
% x = "foo"
<%=x%>
4.
%% print "foo"
5.
%% <%="foo"%>
6.<%="
% print 'foo'
"%>
7.<%="
%% print 'foo'
"%>
EOS
    ans = <<EOS
1.<% : <%%
2.%%> : %>
3.
foo
4.
% print "foo"
5.
% foo
6.
% print 'foo'

7.
%% print 'foo'

EOS
    assert_equal(ans, ERB.new(src, nil, '%').result)
  end

  def test_07_keep_lineno
    src = <<EOS
Hello, 
% x = "World"
<%= x%>
% raise("lineno")
EOS

    erb = ERB.new(src, nil, '%')
    begin
      erb.result
      assert(false)
    rescue
      assert_equal("(erb):4", $@[0].to_s)
    end

    src = <<EOS
%>
Hello, 
<% x = "World%%>
"%>
<%= x%>
EOS

    ans = <<EOS
%>Hello, 
World%>
EOS
    assert_equal(ans, ERB.new(src, nil, '>').result)

    ans = <<EOS
%>
Hello, 

World%>
EOS
    assert_equal(ans, ERB.new(src, nil, '<>').result)

    ans = <<EOS
%>
Hello, 

World%>

EOS
    assert_equal(ans, ERB.new(src).result)

    src = <<EOS
Hello, 
<% x = "World%%>
"%>
<%= x%>
<% raise("lineno") %>
EOS

    erb = ERB.new(src)
    begin
      erb.result
      assert(false)
    rescue
      assert_equal("(erb):5", $@[0].to_s)
    end

    erb = ERB.new(src, nil, '>')
    begin
      erb.result
      assert(false)
    rescue
      assert_equal("(erb):5", $@[0].to_s)
    end

    erb = ERB.new(src, nil, '<>')
    begin
      erb.result
      assert(false)
    rescue
      assert_equal("(erb):5", $@[0].to_s)
    end

    src = <<EOS
% y = 'Hello'
<%- x = "World%%>
"-%>
<%= x %><%- x = nil -%> 
<% raise("lineno") %>
EOS

    erb = ERB.new(src, nil, '-')
    begin
      erb.result
      assert(false)
    rescue
      assert_equal("(erb):5", $@[0].to_s)
    end

    erb = ERB.new(src, nil, '%-')
    begin
      erb.result
      assert(false)
    rescue
      assert_equal("(erb):5", $@[0].to_s)
    end
  end

  def test_08_explicit
    src = <<EOS
<% x = %w(hello world) -%>
NotSkip <%- y = x -%> NotSkip
<% x.each do |w| -%>
  <%- up = w.upcase -%>
  * <%= up %>
<% end -%>
 <%- z = nil -%> NotSkip <%- z = x %>
 <%- z.each do |w| -%>
   <%- down = w.downcase -%>
   * <%= down %>
   <%- up = w.upcase -%>
   * <%= up %>
 <%- end -%>
KeepNewLine <%- z = nil -%> 
EOS

   ans = <<EOS
NotSkip  NotSkip
  * HELLO
  * WORLD
 NotSkip 
   * hello
   * HELLO
   * world
   * WORLD
KeepNewLine  
EOS
   assert_equal(ans, ERB.new(src, nil, '-').result)
   assert_equal(ans, ERB.new(src, nil, '-%').result)
  end
end
