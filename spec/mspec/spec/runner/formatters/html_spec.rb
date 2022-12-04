require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/guards/guard'
require 'mspec/runner/formatters/html'
require 'mspec/runner/mspec'
require 'mspec/runner/example'
require 'mspec/utils/script'
require 'mspec/helpers'

RSpec.describe HtmlFormatter do
  before :each do
    @formatter = HtmlFormatter.new
  end

  it "responds to #register by registering itself with MSpec for appropriate actions" do
    allow(MSpec).to receive(:register)
    expect(MSpec).to receive(:register).with(:start, @formatter)
    expect(MSpec).to receive(:register).with(:enter, @formatter)
    expect(MSpec).to receive(:register).with(:leave, @formatter)
    @formatter.register
  end
end

RSpec.describe HtmlFormatter, "#start" do
  before :each do
    $stdout = @out = IOStub.new
    @formatter = HtmlFormatter.new
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints the HTML head" do
    @formatter.start
    ruby_engine = RUBY_ENGINE
    expect(ruby_engine).to match(/^#{ruby_engine}/)
    expect(@out).to eq(%[<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"
    "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<title>Spec Output For #{ruby_engine} (#{RUBY_VERSION})</title>
<style type="text/css">
ul {
  list-style: none;
}
.fail {
  color: red;
}
.pass {
  color: green;
}
#details :target {
  background-color: #ffffe0;
}
</style>
</head>
<body>
])
  end
end

RSpec.describe HtmlFormatter, "#enter" do
  before :each do
    $stdout = @out = IOStub.new
    @formatter = HtmlFormatter.new
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints the #describe string" do
    @formatter.enter "describe"
    expect(@out).to eq("<div><p>describe</p>\n<ul>\n")
  end
end

RSpec.describe HtmlFormatter, "#leave" do
  before :each do
    $stdout = @out = IOStub.new
    @formatter = HtmlFormatter.new
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints the closing tags for the #describe string" do
    @formatter.leave
    expect(@out).to eq("</ul>\n</div>\n")
  end
end

RSpec.describe HtmlFormatter, "#exception" do
  before :each do
    $stdout = @out = IOStub.new
    @formatter = HtmlFormatter.new
    @formatter.register
    @state = ExampleState.new ContextState.new("describe"), "it"
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints the #it string once for each exception raised" do
    exc = ExceptionState.new @state, nil, SpecExpectationNotMetError.new("disappointing")
    @formatter.exception exc
    exc = ExceptionState.new @state, nil, MSpecExampleError.new("painful")
    @formatter.exception exc
    expect(@out).to eq(%[<li class="fail">- it (<a href="#details-1">FAILED - 1</a>)</li>
<li class="fail">- it (<a href="#details-2">ERROR - 2</a>)</li>
])
  end
end

RSpec.describe HtmlFormatter, "#after" do
  before :each do
    $stdout = @out = IOStub.new
    @formatter = HtmlFormatter.new
    @formatter.register
    @state = ExampleState.new ContextState.new("describe"), "it"
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints the #it once when there are no exceptions raised" do
    @formatter.after @state
    expect(@out).to eq(%[<li class="pass">- it</li>\n])
  end

  it "does not print any output if an exception is raised" do
    exc = ExceptionState.new @state, nil, SpecExpectationNotMetError.new("disappointing")
    @formatter.exception exc
    out = @out.dup
    @formatter.after @state
    expect(@out).to eq(out)
  end
end

RSpec.describe HtmlFormatter, "#finish" do
  before :each do
    @tally = double("tally").as_null_object
    allow(TallyAction).to receive(:new).and_return(@tally)
    @timer = double("timer").as_null_object
    allow(TimerAction).to receive(:new).and_return(@timer)

    @out = tmp("HtmlFormatter")

    context = ContextState.new "describe"
    @state = ExampleState.new(context, "it")
    allow(MSpec).to receive(:register)
    @formatter = HtmlFormatter.new(@out)
    @formatter.register
    @exception = MSpecExampleError.new("broken")
    allow(@exception).to receive(:backtrace).and_return(["file.rb:1", "file.rb:2"])
  end

  after :each do
    rm_r @out
  end

  it "prints a failure message for an exception" do
    exc = ExceptionState.new @state, nil, @exception
    @formatter.exception exc
    @formatter.finish
    output = File.read(@out)
    expect(output).to include "<p>describe it ERROR</p>"
  end

  it "prints a backtrace for an exception" do
    exc = ExceptionState.new @state, nil, @exception
    allow(exc).to receive(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @formatter.finish
    output = File.read(@out)
    expect(output).to match(%r[<pre>.*path/to/some/file.rb:35:in method.*</pre>]m)
  end

  it "prints a summary of elapsed time" do
    expect(@timer).to receive(:format).and_return("Finished in 2.0 seconds")
    @formatter.finish
    output = File.read(@out)
    expect(output).to include "<p>Finished in 2.0 seconds</p>\n"
  end

  it "prints a tally of counts" do
    expect(@tally).to receive(:format).and_return("1 example, 0 failures")
    @formatter.finish
    output = File.read(@out)
    expect(output).to include '<p class="pass">1 example, 0 failures</p>'
  end

  it "prints errors, backtraces, elapsed time, and tallies" do
    exc = ExceptionState.new @state, nil, @exception
    allow(exc).to receive(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc

    expect(@timer).to receive(:format).and_return("Finished in 2.0 seconds")
    expect(@tally).to receive(:format).and_return("1 example, 1 failures")
    @formatter.finish
    output = File.read(@out)
    expect(output).to eq(%[<li class=\"fail\">- it (<a href=\"#details-1\">ERROR - 1</a>)</li>
<hr>
<ol id="details">
<li id="details-1"><p>describe it ERROR</p>
<p>MSpecExampleError: broken</p>
<pre>
path/to/some/file.rb:35:in method</pre>
</li>
</ol>
<p>Finished in 2.0 seconds</p>
<p class="fail">1 example, 1 failures</p>
</body>
</html>
])
  end
end
