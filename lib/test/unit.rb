# :include: ../../../../README
#
# ----
#
# = Usage
#
# The general idea behind unit testing is that you write a _test_
# _method_ that makes certain _assertions_ about your code, working
# against a _test_ _fixture_. A bunch of these _test_ _methods_ are
# bundled up into a _test_ _suite_ and can be run any time the
# developer wants. The results of a run are gathered in a _test_
# _result_ and displayed to the user through some UI. So, lets break
# this down and see how Test::Unit provides each of these necessary
# pieces.
#
#
# == Assertions
#
# These are the heart of the framework. Think of an assertion as a
# statement of expected outcome, i.e. "I assert that x should be equal
# to y". If, when the assertion is executed, it turns out to be
# correct, nothing happens, and life is good. If, on the other hand,
# your assertion turns out to be false, an error is propagated with
# pertinent information so that you can go back and make your
# assertion succeed, and, once again, life is good. For an explanation
# of the current assertions, see Test::Unit::Assertions.
#
#
# == Test Method & Test Fixture
#
# Obviously, these assertions have to be called within a context that
# knows about them and can do something meaningful with their
# pass/fail value. Also, it's handy to collect a bunch of related
# tests, each test represented by a method, into a common test class
# that knows how to run them. The tests will be in a separate class
# from the code they're testing for a couple of reasons. First of all,
# it allows your code to stay uncluttered with test code, making it
# easier to maintain. Second, it allows the tests to be stripped out
# for deployment, since they're really there for you, the developer,
# and your users don't need them. Third, and most importantly, it
# allows you to set up a common test fixture for your tests to run
# against.
#
# What's a test fixture? Well, tests do not live in a vacuum; rather,
# they're run against the code they are testing. Often, a collection
# of tests will run against a common set of data, also called a
# fixture. If they're all bundled into the same test class, they can
# all share the setting up and tearing down of that data, eliminating
# unnecessary duplication and making it much easier to add related
# tests.
#
# Test::Unit::TestCase wraps up a collection of test methods together
# and allows you to easily set up and tear down the same test fixture
# for each test. This is done by overriding #setup and/or #teardown,
# which will be called before and after each test method that is
# run. The TestCase also knows how to collect the results of your
# assertions into a Test::Unit::TestResult, which can then be reported
# back to you... but I'm getting ahead of myself. To write a test,
# follow these steps:
#
# * Make sure Test::Unit is in your library path.
# * require 'test/unit' in your test script.
# * Create a class that subclasses Test::Unit::TestCase.
# * Add a method that begins with "test" to your class.
# * Make assertions in your test method.
# * Optionally define #setup and/or #teardown to set up and/or tear
#   down your common test fixture.
# * You can now run your test as you would any other Ruby
#   script... try it and see!
#
# A really simple test might look like this (#setup and #teardown are
# commented out to indicate that they are completely optional):
#
#     require 'test/unit'
#     
#     class TC_MyTest < Test::Unit::TestCase
#       # def setup
#       # end
#     
#       # def teardown
#       # end
#     
#       def test_fail
#         assert(false, 'Assertion was false.')
#       end
#     end
#
#
# == Test Runners
#
# So, now you have this great test class, but you still need a way to
# run it and view any failures that occur during the run. This is
# where Test::Unit::UI::Console::TestRunner (and others, such as
# Test::Unit::UI::GTK::TestRunner) comes into play. The console test
# runner is automatically invoked for you if you require 'test/unit'
# and simply run the file. To use another runner, or to manually
# invoke a runner, simply call its run class method and pass in an
# object that responds to the suite message with a
# Test::Unit::TestSuite. This can be as simple as passing in your
# TestCase class (which has a class suite method). It might look
# something like this:
#
#    require 'test/unit/ui/console/testrunner'
#    Test::Unit::UI::Console::TestRunner.run(TC_MyTest)
#
#
# == Test Suite
#
# As more and more unit tests accumulate for a given project, it
# becomes a real drag running them one at a time, and it also
# introduces the potential to overlook a failing test because you
# forget to run it. Suddenly it becomes very handy that the
# TestRunners can take any object that returns a Test::Unit::TestSuite
# in response to a suite method. The TestSuite can, in turn, contain
# other TestSuites or individual tests (typically created by a
# TestCase). In other words, you can easily wrap up a group of
# TestCases and TestSuites like this:
#
#  require 'test/unit/testsuite'
#  require 'tc_myfirsttests'
#  require 'tc_moretestsbyme'
#  require 'ts_anothersetoftests'
#
#  class TS_MyTests
#    def self.suite
#      suite = Test::Unit::TestSuite.new
#      suite << TC_MyFirstTests.suite
#      suite << TC_MoreTestsByMe.suite
#      suite << TS_AnotherSetOfTests.suite
#      return suite
#    end
#  end
#  Test::Unit::UI::Console::TestRunner.run(TS_MyTests)
#
# Now, this is a bit cumbersome, so Test::Unit does a little bit more
# for you, by wrapping these up automatically when you require
# 'test/unit'. What does this mean? It means you could write the above
# test case like this instead:
#
#  require 'test/unit'
#  require 'tc_myfirsttests'
#  require 'tc_moretestsbyme'
#  require 'ts_anothersetoftests'
#
# Test::Unit is smart enough to find all the test cases existing in
# the ObjectSpace and wrap them up into a suite for you. It then runs
# the dynamic suite using the console TestRunner.
#
#
# == Questions?
#
# I'd really like to get feedback from all levels of Ruby
# practitioners about typos, grammatical errors, unclear statements,
# missing points, etc., in this document (or any other).




require 'test/unit/testcase'
require 'test/unit/ui/testrunnermediator'

at_exit {
  # We can't debug tests run with at_exit unless we add the following:
  set_trace_func DEBUGGER__.context.method(:trace_func).to_proc if (defined? DEBUGGER__)

  if (!Test::Unit::UI::TestRunnerMediator.run?)
    suite_name = $0.sub(/\.rb$/, '')
    suite = Test::Unit::TestSuite.new(suite_name)
    test_classes = []
    ObjectSpace.each_object(Class) {
      | klass |
      test_classes << klass if (Test::Unit::TestCase > klass)
    }

    runners = {
      '--console' => proc do |suite|
        require 'test/unit/ui/console/testrunner'
        passed = Test::Unit::UI::Console::TestRunner.run(suite).passed?
	exit(passed ? 0 : 1)
      end,
      '--gtk' => proc do |suite|
        require 'test/unit/ui/gtk/testrunner'
        Test::Unit::UI::GTK::TestRunner.run(suite)
      end,
      '--fox' => proc do |suite|
        require 'test/unit/ui/fox/testrunner'
        Test::Unit::UI::Fox::TestRunner.run(suite)
      end,
    }
        
    unless (ARGV.empty?)
      runner = runners[ARGV[0]]
      ARGV.shift unless (runner.nil?)
    end
    runner = runners['--console'] if (runner.nil?)

    if ARGV.empty?
      test_classes.each { |klass| suite << klass.suite }
    else
      tests = test_classes.map { |klass| klass.suite.tests }.flatten
      criteria = ARGV.map { |arg| (arg =~ %r{^/(.*)/$}) ? Regexp.new($1) : arg }
      criteria.each {
        | criterion |
        if (criterion.instance_of?(Regexp))
          tests.each { |test| suite << test if (criterion =~ test.name) }
        elsif (/^A-Z/ =~ criterion)
          tests.each { |test| suite << test if (criterion == test.class.name) }
        else
          tests.each { |test| suite << test if (criterion == test.method_name) }
        end
      }
    end
    runner.call(suite)
  end
}
