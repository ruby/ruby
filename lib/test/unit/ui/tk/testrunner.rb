# :nodoc:
#
# Original Author:: Nathaniel Talbott.
# Author:: Kazuhiro NISHIYAMA.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# Copyright:: Copyright (c) 2003 Kazuhiro NISHIYAMA. All rights reserved.
# License:: Ruby license.

require 'tk'
require 'test/unit/ui/testrunnermediator'
require 'test/unit/ui/testrunnerutilities'

module Test
  module Unit
    module UI
      module Tk # :nodoc:

        # Runs a Test::Unit::TestSuite in a Tk UI. Obviously,
        # this one requires you to have Tk
        # and the Ruby Tk extension installed.
        class TestRunner
          extend TestRunnerUtilities

          # Creates a new TestRunner and runs the suite.
          def self.run(suite)
            new(suite).start

          end

          # Creates a new TestRunner for running the passed
          # suite.
          def initialize(suite)
            if (suite.respond_to?(:suite))
              @suite = suite.suite
            else
              @suite = suite
            end

            @red = false
            @fault_detail_list = []
            @run_suite_thread = nil
          end

          # Begins the test run.
          def start
            setup_ui
            setup_mediator
            attach_to_mediator
            start_ui
          end

          private
          def setup_mediator # :nodoc:
            @mediator = TestRunnerMediator.new(@suite)
            suite_name = @suite.to_s
            if ( @suite.kind_of?(Module) )
              suite_name = @suite.name
            end
            @suite_name_entry.value = suite_name
          end

          def attach_to_mediator # :nodoc:
            @run_button.command(method(:run_suite))
            @fault_list.bind('ButtonPress-1', proc{|y|
              fault = @fault_detail_list[@fault_list.nearest(y)]
              if fault
                show_fault(fault)
              end
            }, '%y')
            @mediator.add_listener(TestRunnerMediator::RESET, &method(:reset_ui))
            @mediator.add_listener(TestResult::FAULT, &method(:add_fault))
            @mediator.add_listener(TestResult::CHANGED, &method(:result_changed))
            @mediator.add_listener(TestRunnerMediator::STARTED, &method(:started))
            @mediator.add_listener(TestCase::STARTED, &method(:test_started))
            @mediator.add_listener(TestRunnerMediator::FINISHED, &method(:finished))
          end

          def start_ui # :nodoc:
            run_suite
            begin
              ::Tk.mainloop
            rescue Exception
              if @run_suite_thread and @run_suite_thread.alive?
                @run_suite_thread.raise $!
                retry
              else
                raise
              end
            end
          end

          def stop # :nodoc:
            ::Tk.exit
          end

          def reset_ui(count) # :nodoc:
            @test_total_count = count.to_f
            @test_progress_bar.configure('background'=>'green')
            @test_progress_bar.place('relwidth'=>0/count)
            @red = false

            @test_count_label.value = 0
            @assertion_count_label.value = 0
            @failure_count_label.value = 0
            @error_count_label.value = 0

            @fault_list.delete(0, 'end')
            @fault_detail_list = []
            clear_fault
          end

          def add_fault(fault) # :nodoc:
            if ( ! @red )
              @test_progress_bar.configure('background'=>'red')
              @red = true
            end
            @fault_detail_list.push fault
            @fault_list.insert('end', fault.short_display)
          end

          def show_fault(fault) # :nodoc:
            raw_show_fault(fault.long_display)
          end

          def raw_show_fault(string) # :nodoc:
            @detail_text.value = string
          end

          def clear_fault # :nodoc:
            raw_show_fault("")
          end

          def result_changed(result) # :nodoc:
            @test_count_label.value = result.run_count
            @test_progress_bar.place('relwidth'=>result.run_count/@test_total_count)
            @assertion_count_label.value = result.assertion_count
            @failure_count_label.value = result.failure_count
            @error_count_label.value = result.error_count
          end

          def started(result) # :nodoc:
            output_status("Started...")
          end

          def test_started(test_name)
            output_status("Running #{test_name}...")
          end

          def finished(elapsed_time)
            output_status("Finished in #{elapsed_time} seconds")
          end

          def output_status(string) # :nodoc:
            @status_entry.value = string
          end

          def setup_ui # :nodoc:
            @status_entry = TkVariable.new
            l = TkLabel.new(nil, 'textvariable'=>@status_entry, 'relief'=>'sunken')
            l.pack('side'=>'bottom', 'fill'=>'x')

            suite_frame = TkFrame.new.pack('fill'=>'x')

            @run_button = TkButton.new(suite_frame, 'text'=>'Run')
            @run_button.pack('side'=>'right')

            TkLabel.new(suite_frame, 'text'=>'Suite:').pack('side'=>'left')
            @suite_name_entry = TkVariable.new
            l = TkLabel.new(suite_frame, 'textvariable'=>@suite_name_entry, 'relief'=>'sunken')
            l.pack('side'=>'left', 'fill'=>'x', 'expand'=>true)

            f = TkFrame.new(nil, 'relief'=>'sunken', 'borderwidth'=>3, 'height'=>20).pack('fill'=>'x', 'padx'=>1)
            @test_progress_bar = TkFrame.new(f, 'background'=>'green').place('anchor'=>'nw', 'relwidth'=>0.0, 'relheight'=>1.0)

            info_frame = TkFrame.new.pack('fill'=>'x')
            @test_count_label = create_count_label(info_frame, 'Tests:')
            @assertion_count_label = create_count_label(info_frame, 'Assertions:')
            @failure_count_label = create_count_label(info_frame, 'Failures:')
            @error_count_label = create_count_label(info_frame, 'Errors:')

            fault_list_frame = TkFrame.new.pack('fill'=>'both', 'expand'=>true)

            fault_scrollbar = TkScrollbar.new(fault_list_frame)
            fault_scrollbar.pack('side'=>'right', 'fill'=>'y')
            @fault_list = TkListbox.new(fault_list_frame)
            @fault_list.pack('fill'=>'both', 'expand'=>true)
            @fault_list.yscrollbar(fault_scrollbar)

            detail_frame = TkFrame.new.pack('fill'=>'both', 'expand'=>true)
            detail_scrollbar_y = TkScrollbar.new(detail_frame)
            detail_scrollbar_y.pack('side'=>'right', 'fill'=>'y')
            detail_scrollbar_x = TkScrollbar.new(detail_frame)
            detail_scrollbar_x.pack('side'=>'bottom', 'fill'=>'x')
            @detail_text = TkText.new(detail_frame, 'height'=>10, 'wrap'=>'none') {
              bindtags(bindtags - [TkText])
            }
            @detail_text.pack('fill'=>'both', 'expand'=>true)
            @detail_text.yscrollbar(detail_scrollbar_y)
            @detail_text.xscrollbar(detail_scrollbar_x)
          end

          def create_count_label(parent, label) # :nodoc:
            TkLabel.new(parent, 'text'=>label).pack('side'=>'left', 'expand'=>true)
            v = TkVariable.new(0)
            TkLabel.new(parent, 'textvariable'=>v).pack('side'=>'left', 'expand'=>true)
            v
          end

          def run_suite # :nodoc:
            run_proc = proc {
              @run_suite_thread = Thread.start {
                @mediator.run_suite
              }
            }
            TkAfter.new(1000, 1, run_proc).start
          end
        end
      end
    end
  end
end

if __FILE__ == $0
  Test::Unit::UI::Tk::TestRunner.start_command_line_test
end
