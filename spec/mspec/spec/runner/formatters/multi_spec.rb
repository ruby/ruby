require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/dotted'
require 'mspec/runner/formatters/multi'
require 'mspec/runner/example'
require 'yaml'

describe MultiFormatter, "#aggregate_results" do
  before :each do
    @stdout, $stdout = $stdout, IOStub.new

    @file = double("file").as_null_object

    File.stub(:delete)
    File.stub(:read)

    @hash = { "files"=>1, "examples"=>1, "expectations"=>2, "failures"=>0, "errors"=>0 }
    YAML.stub(:load).and_return(@hash)

    @formatter = DottedFormatter.new.extend(MultiFormatter)
    @formatter.timer.stub(:format).and_return("Finished in 42 seconds")
  end

  after :each do
    $stdout = @stdout
  end

  it "outputs a summary without errors" do
    @formatter.aggregate_results(["a", "b"])
    @formatter.finish
    $stdout.should ==
%[

Finished in 42 seconds

2 files, 2 examples, 4 expectations, 0 failures, 0 errors, 0 tagged
]
  end

  it "outputs a summary with errors" do
    @hash["exceptions"] = [
      "Some#method works real good FAILED\nExpected real good\n to equal fail\n\nfoo.rb:1\nfoo.rb:2",
      "Some#method never fails ERROR\nExpected 5\n to equal 3\n\nfoo.rb:1\nfoo.rb:2"
    ]
    @formatter.aggregate_results(["a"])
    @formatter.finish
    $stdout.should ==
%[

1)
Some#method works real good FAILED
Expected real good
 to equal fail

foo.rb:1
foo.rb:2

2)
Some#method never fails ERROR
Expected 5
 to equal 3

foo.rb:1
foo.rb:2

Finished in 42 seconds

1 file, 1 example, 2 expectations, 0 failures, 0 errors, 0 tagged
]
  end
end
