# = Test::Unit - Ruby Unit Testing Framework
# 
# == Introduction
# 
# Unit testing is making waves all over the place, largely due to the
# fact that it is a core practice of XP. While XP is great, unit testing
# has been around for a long time and has always been a good idea. One
# of the keys to good unit testing, though, is not just writing tests,
# but having tests. What's the difference? Well, if you just _write_ a
# test and throw it away, you have no guarantee that something won't
# change later which breaks your code. If, on the other hand, you _have_
# tests (obviously you have to write them first), and run them as often
# as possible, you slowly build up a wall of things that cannot break
# without you immediately knowing about it. This is when unit testing
# hits its peak usefulness.
# 
# Enter Test::Unit, a framework for unit testing in Ruby, helping you to
# design, debug and evaluate your code by making it easy to write and
# have tests for it.
# 
# 
# == Installation
# 
# Run:
# * ruby setup.rb config
# * ruby setup.rb setup
# * ruby setup.rb install
# 
# Note that the runit compatibility layer will *not* be installed if you
# already have RubyUnit installed.
# 
# Mac OS X users should also note that setup.rb will fail unless they
# execute 'unlimit stacksize' before running it.
# 
# 
# == Notes
# 
# Test::Unit has grown out of and superceded Lapidary.
# 
# 
# == Feedback
# 
# I like (and do my best to practice) XP, so I value early releases,
# user feedback, and clean, simple, expressive code. There is always
# room for improvement in everything I do, and Test::Unit is no
# exception. Please, let me know what you think of Test::Unit as it
# stands, and what you'd like to see expanded/changed/improved/etc. If
# you find a bug, let me know ASAP; one good way to let me know what the
# bug is is to submit a new test that catches it :-) Also, I'd love to
# hear about any successes you have with Test::Unit, and any
# documentation you might add will be greatly appreciated. My contact
# info is below.
# 
# 
# == Contact Information
# 
# A lot of discussion happens about Ruby in general on the ruby-talk
# mailing list (http://www.ruby-lang.org/en/ml.html), and you can ask
# any questions you might have there. I monitor the list, as do many
# other helpful Rubyists, and you're sure to get a quick answer. Of
# course, you're also welcome to email me (Nathaniel Talbott) directly
# at mailto:testunit@talbott.ws, and I'll do my best to help you out.
# 
# 
# == Credits
# 
# I'd like to thank...
# 
# Matz, for a great language!
# 
# Masaki Suketa, for his work on RubyUnit, which filled a vital need in
# the Ruby world for a very long time. I'm also grateful for his help in
# polishing Test::Unit and getting the RubyUnit compatibility layer
# right. His graciousness in allowing Test::Unit to supercede RubyUnit
# continues to be a challenge to me to be more willing to defer my own
# rights.
# 
# Ken McKinlay, for his interest and work on unit testing, and for his
# willingness to dialog about it. He was also a great help in pointing
# out some of the holes in the RubyUnit compatibility layer.
# 
# Dave Thomas, for the original idea that led to the extremely simple
# "require 'test/unit'", plus his code to improve it even more by
# allowing the selection of tests from the command-line. Also, without
# RDoc, the documentation for Test::Unit would stink a lot more than it
# does now.
# 
# Everyone who's helped out with bug reports, feature ideas,
# encouragement to continue, etc. It's a real privilege to be a part of
# the Ruby community.
# 
# The guys at RoleModel Software, for putting up with me repeating, "But
# this would be so much easier in Ruby!" whenever we're coding in Java.
# 
# My Creator, for giving me life, and giving it more abundantly.
# 
# 
# == License
# 
# Test::Unit is copyright (c) 2000-2003 Nathaniel Talbott. It is free
# software, and is distributed under the Ruby license. See the COPYING
# file in the standard Ruby distribution for details.
# 
# 
# == Warranty
# 
# This software is provided "as is" and without any express or
# implied warranties, including, without limitation, the implied
# warranties of merchantibility and fitness for a particular
# purpose.
# 
# 
# == Author
# 
# Nathaniel Talbott.
# Copyright (c) 2000-2003, Nathaniel Talbott
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
require 'test/unit/collector/objectspace'

at_exit {
  require 'optparse'
  if (!Test::Unit::UI::TestRunnerMediator.run?)
    output_level = nil
    runners = {
      :console => proc do |suite|
        require 'test/unit/ui/console/testrunner'
        output_level ||= Test::Unit::UI::Console::TestRunner::NORMAL
        passed = Test::Unit::UI::Console::TestRunner.run(suite, output_level).passed?
	exit(passed ? 0 : 1)
      end,
      :gtk => proc do |suite|
        require 'test/unit/ui/gtk/testrunner'
        Test::Unit::UI::GTK::TestRunner.run(suite)
      end,
      :fox => proc do |suite|
        require 'test/unit/ui/fox/testrunner'
        Test::Unit::UI::Fox::TestRunner.run(suite)
      end,
    }
    
    runner = runners[:console]
    filters = []
    catch(:stop_processing) do
      ARGV.options do |o|
        o.program_name = "test/unit.rb"
        o.banner = "Test::Unit automatic runner."
        o.banner = "#{$0} [options] [-- untouched arguments]"

        o.on
        runner_display = runners.keys.collect{|r| r.to_s.sub(/^(.)/, '[\\1]')}.join(", ")
        o.on('-r', '--runner=RUNNER', runners.keys,
          "Use the given runner.",
          "(" + runner_display + ")"){|r| runner = runners[r]}
        o.on('-n', '--name=NAME', String,
          "Runs tests matching NAME",
          "(patterns may be used).") do |n|
          n = (%r{\A/(.*)/\Z} =~ n ? Regexp.new($1) : n)
          case n
            when Regexp
              filters << proc{|t| n =~ t.method_name}
            else
              filters << proc{|t| n == t.method_name}
          end
        end
        o.on('-t', '--testcase=TESTCASE', String,
          "Runs tests in TestCases matching TESTCASE",
          "(patterns may be used).") do |n|
          n = (%r{\A/(.*)/\Z} =~ n ? Regexp.new($1) : n)
          case n
            when Regexp
              filters << proc{|t| n =~ t.class.name}
            else
              filters << proc{|t| n == t.class.name}
          end
        end
        o.on('-v', '--verbose=[LEVEL]', (0..3).to_a.collect{|i| i.to_s},
          "Set output level.",
          "Levels are:",
          "  0 = SILENT",
          "  1 = PROGRESS_ONLY",
          "  2 = NORMAL",
          "  3 = VERBOSE (default)",
          "  Only valid for the console runner."){|l| output_level = (l ? l.to_i : 3)}
        o.on('--',
          "Stop processing options so that",
          "remaining options will be passed",
          "to the test."){throw :stop_processing}
        o.on('-h', '--help', 'Display this help.'){puts o; exit(0)}

        o.on_tail
        o.on_tail('Deprecated options:')
        o.on_tail('--console', 'Console runner (use --runner).') do
          warn("Deprecated option (--console).")
          runner = runners[:console]
        end
        o.on_tail('--gtk', 'GTK runner (use --runner).') do
          warn("Deprecated option (--gtk).")
          runner = runners[:gtk]
        end
        o.on_tail('--fox', 'Fox runner (use --runner).') do
          warn("Deprecated option (--fox).")
          runner = runners[:fox]
        end
        o.on_tail

        begin
          o.parse!
        rescue OptionParser::ParseError => e
          puts e
          puts o
          exit(1)
        end
      end
    end

    if(output_level && !(runner == runners[:console]))
      puts "Invalid arguments: You can only specify an output level with the console runner."
      exit(1)
    end

    collector = Test::Unit::Collector::ObjectSpace::new
    collector.filter = filters

    suite_name = $0.sub(/\.rb$/, '')
    runner.call(collector.collect(suite_name))
  end
}
