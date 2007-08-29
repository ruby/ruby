#--
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
      module Tk

        # Runs a Test::Unit::TestSuite in a Tk UI. Obviously,
        # this one requires you to have Tk
        # and the Ruby Tk extension installed.
        class TestRunner
          extend TestRunnerUtilities

          # Creates a new TestRunner for running the passed
          # suite.
          def initialize(suite, output_level = NORMAL)
            if (suite.respond_to?(:suite))
              @suite = suite.suite
            else
              @suite = suite
            end
            @result = nil

            @red = false
            @fault_detail_list = []
            @runner = Thread.current
            @restart_signal = Class.new(Exception)
            @viewer = Thread.start do
              @runner.join rescue @runner.run
              ::Tk.mainloop
            end
            @viewer.join rescue nil # wait deadlock to handshake
          end

          # Begins the test run.
          def start
            setup_ui
            setup_mediator
            attach_to_mediator
            start_ui
            @result
          end

          private
          def setup_mediator
            @mediator = TestRunnerMediator.new(@suite)
            suite_name = @suite.to_s
            if ( @suite.kind_of?(Module) )
              suite_name = @suite.name
            end
            @suite_name_entry.value = suite_name
          end

          def attach_to_mediator
            @run_button.command(method(:run_test))
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

          def run_test
            @runner.raise(@restart_signal)
          end

          def start_ui
            @viewer.run
            running = false
            begin
              loop do
                if (running ^= true)
                  @run_button.configure('text'=>'Stop')
                  @mediator.run_suite
                else
                  @run_button.configure('text'=>'Run')
                  @viewer.join
                  break
                end
              end
            rescue @restart_signal
              retry
            rescue
            end
          end

          def stop
            ::Tk.exit
          end

          def reset_ui(count)
            @test_total_count = count.to_f
            @test_progress_bar.configure('background'=>'green')
            @test_progress_bar.place('relwidth'=>(count.zero? ? 0 : 0/count))
            @red = false

            @test_count_label.value = 0
            @assertion_count_label.value = 0
            @failure_count_label.value = 0
            @error_count_label.value = 0

            @fault_list.delete(0, 'end')
            @fault_detail_list = []
            clear_fault
          end

          def add_fault(fault)
            if ( ! @red )
              @test_progress_bar.configure('background'=>'red')
              @red = true
            end
            @fault_detail_list.push fault
            @fault_list.insert('end', fault.short_display)
          end

          def show_fault(fault)
            raw_show_fault(fault.long_display)
          end

          def raw_show_fault(string)
            @detail_text.value = string
          end

          def clear_fault
            raw_show_fault("")
          end

          def result_changed(result)
            @test_count_label.value = result.run_count
            @test_progress_bar.place('relwidth'=>result.run_count/@test_total_count)
            @assertion_count_label.value = result.assertion_count
            @failure_count_label.value = result.failure_count
            @error_count_label.value = result.error_count
          end

          def started(result)
            @result = result
            output_status("Started...")
          end

          def test_started(test_name)
            output_status("Running #{test_name}...")
          end

          def finished(elapsed_time)
            output_status("Finished in #{elapsed_time} seconds")
          end

          def output_status(string)
            @status_entry.value = string
          end

          def setup_ui
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

	    if (::Tk.info('command', TkPanedWindow::TkCommandNames[0]) != "")
	      # use panedwindow
	      paned_frame = TkPanedWindow.new("orient"=>"vertical").pack('fill'=>'both', 'expand'=>true)

	      fault_list_frame = TkFrame.new(paned_frame)
	      detail_frame = TkFrame.new(paned_frame)

	      paned_frame.add(fault_list_frame, detail_frame)
	    else
	      # no panedwindow
	      paned_frame = nil
	      fault_list_frame = TkFrame.new.pack('fill'=>'both', 'expand'=>true)
	      detail_frame = TkFrame.new.pack('fill'=>'both', 'expand'=>true)
	    end

	    TkGrid.rowconfigure(fault_list_frame, 0, 'weight'=>1, 'minsize'=>0)
	    TkGrid.columnconfigure(fault_list_frame, 0, 'weight'=>1, 'minsize'=>0)

            fault_scrollbar_y = TkScrollbar.new(fault_list_frame)
            fault_scrollbar_x = TkScrollbar.new(fault_list_frame)
            @fault_list = TkListbox.new(fault_list_frame)
            @fault_list.yscrollbar(fault_scrollbar_y)
            @fault_list.xscrollbar(fault_scrollbar_x)

	    TkGrid.rowconfigure(detail_frame, 0, 'weight'=>1, 'minsize'=>0)
	    TkGrid.columnconfigure(detail_frame, 0, 'weight'=>1, 'minsize'=>0)

	    ::Tk.grid(@fault_list, fault_scrollbar_y, 'sticky'=>'news')
	    ::Tk.grid(fault_scrollbar_x, 'sticky'=>'news')

            detail_scrollbar_y = TkScrollbar.new(detail_frame)
            detail_scrollbar_x = TkScrollbar.new(detail_frame)
            @detail_text = TkText.new(detail_frame, 'height'=>10, 'wrap'=>'none') {
              bindtags(bindtags - [TkText])
	    }
	    @detail_text.yscrollbar(detail_scrollbar_y)
	    @detail_text.xscrollbar(detail_scrollbar_x)

	    ::Tk.grid(@detail_text, detail_scrollbar_y, 'sticky'=>'news')
	    ::Tk.grid(detail_scrollbar_x, 'sticky'=>'news')

	    # rubber-style pane
	    if paned_frame
	      ::Tk.update
	      @height = paned_frame.winfo_height
	      paned_frame.bind('Configure', proc{|h|
		paned_frame.sash_place(0, 0, paned_frame.sash_coord(0)[1] * h / @height)
		@height = h
	      }, '%h')
	    end
          end

          def create_count_label(parent, label)
            TkLabel.new(parent, 'text'=>label).pack('side'=>'left', 'expand'=>true)
            v = TkVariable.new(0)
            TkLabel.new(parent, 'textvariable'=>v).pack('side'=>'left', 'expand'=>true)
            v
          end
        end
      end
    end
  end
end

if __FILE__ == $0
  Test::Unit::UI::Tk::TestRunner.start_command_line_test
end
