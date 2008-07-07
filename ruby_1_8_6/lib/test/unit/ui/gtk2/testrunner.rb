#--
#
# Author:: Kenta MURATA.
# Copyright:: Copyright (c) 2000-2002 Kenta MURATA. All rights reserved.
# License:: Ruby license.

require "gtk2"
require "test/unit/ui/testrunnermediator"
require "test/unit/ui/testrunnerutilities"

module Test
  module Unit
    module UI
      module GTK2

        Gtk.init

        class EnhancedLabel < Gtk::Label
          def set_text(text)
            super(text.gsub(/\n\t/, "\n    "))
          end
        end

        class FaultList < Gtk::TreeView
          def initialize
            @faults = []
            @model = Gtk::ListStore.new(String, String)
            super(@model)
            column = Gtk::TreeViewColumn.new
            column.visible = false
            append_column(column)
            renderer = Gtk::CellRendererText.new
            column = Gtk::TreeViewColumn.new("Failures", renderer, {:text => 1})
            append_column(column)
            selection.mode = Gtk::SELECTION_SINGLE
            set_rules_hint(true)
            set_headers_visible(false)
          end # def initialize

          def add_fault(fault)
            @faults.push(fault)
            iter = @model.append
            iter.set_value(0, (@faults.length - 1).to_s)
            iter.set_value(1, fault.short_display)
          end # def add_fault(fault)

          def get_fault(iter)
            @faults[iter.get_value(0).to_i]
          end # def get_fault

          def clear
            model.clear
          end # def clear
        end

        class TestRunner
          extend TestRunnerUtilities

          def lazy_initialize(symbol)
            if !instance_eval("defined?(@#{symbol})") then
              yield
            end
            return instance_eval("@#{symbol}")
          end
          private :lazy_initialize

          def status_entry
            lazy_initialize(:status_entry) do
              @status_entry = Gtk::Entry.new
              @status_entry.editable = false
            end
          end
          private :status_entry

          def status_panel
            lazy_initialize(:status_panel) do
              @status_panel = Gtk::HBox.new
              @status_panel.border_width = 10
              @status_panel.pack_start(status_entry, true, true, 0)
            end
          end
          private :status_panel

          def fault_detail_label
            lazy_initialize(:fault_detail_label) do
              @fault_detail_label = EnhancedLabel.new("")
#              style = Gtk::Style.new
#              font = Gdk::Font.
#               font_load("-*-Courier 10 Pitch-medium-r-normal--*-120-*-*-*-*-*-*")
#              style.set_font(font)
#              @fault_detail_label.style = style
              @fault_detail_label.justify = Gtk::JUSTIFY_LEFT
              @fault_detail_label.wrap = false
            end
          end
          private :fault_detail_label

          def inner_detail_sub_panel
            lazy_initialize(:inner_detail_sub_panel) do
              @inner_detail_sub_panel = Gtk::HBox.new
              @inner_detail_sub_panel.pack_start(fault_detail_label, false, false, 0)
            end
          end
          private :inner_detail_sub_panel

          def outer_detail_sub_panel
            lazy_initialize(:outer_detail_sub_panel) do
              @outer_detail_sub_panel = Gtk::VBox.new
              @outer_detail_sub_panel.pack_start(inner_detail_sub_panel, false, false, 0)
            end
          end
          private :outer_detail_sub_panel

          def detail_scrolled_window
            lazy_initialize(:detail_scrolled_window) do
              @detail_scrolled_window = Gtk::ScrolledWindow.new
              @detail_scrolled_window.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
              @detail_scrolled_window.
                set_size_request(400, @detail_scrolled_window.allocation.height)
              @detail_scrolled_window.add_with_viewport(outer_detail_sub_panel)
            end
          end
          private :detail_scrolled_window

          def detail_panel
            lazy_initialize(:detail_panel) do
              @detail_panel = Gtk::HBox.new
              @detail_panel.border_width = 10
              @detail_panel.pack_start(detail_scrolled_window, true, true, 0)
            end
          end
          private :detail_panel

          def fault_list
            lazy_initialize(:fault_list) do
              @fault_list = FaultList.new
            end
          end
          private :fault_list

          def list_scrolled_window
            lazy_initialize(:list_scrolled_window) do
              @list_scrolled_window = Gtk::ScrolledWindow.new
              @list_scrolled_window.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
              @list_scrolled_window.
                set_size_request(@list_scrolled_window.allocation.width, 150)
              @list_scrolled_window.add_with_viewport(fault_list)
            end
          end
          private :list_scrolled_window

          def list_panel
            lazy_initialize(:list_panel) do
              @list_panel = Gtk::HBox.new
              @list_panel.border_width = 10
              @list_panel.pack_start(list_scrolled_window, true, true, 0)
            end
          end
          private :list_panel

          def error_count_label
            lazy_initialize(:error_count_label) do
              @error_count_label = Gtk::Label.new("0")
              @error_count_label.justify = Gtk::JUSTIFY_LEFT
            end
          end
          private :error_count_label

          def failure_count_label
            lazy_initialize(:failure_count_label) do
              @failure_count_label = Gtk::Label.new("0")
              @failure_count_label.justify = Gtk::JUSTIFY_LEFT
            end
          end
          private :failure_count_label

          def assertion_count_label
            lazy_initialize(:assertion_count_label) do
              @assertion_count_label = Gtk::Label.new("0")
              @assertion_count_label.justify = Gtk::JUSTIFY_LEFT
            end
          end
          private :assertion_count_label

          def run_count_label
            lazy_initialize(:run_count_label) do
              @run_count_label = Gtk::Label.new("0")
              @run_count_label.justify = Gtk::JUSTIFY_LEFT
            end
          end
          private :run_count_label
          
          def info_panel
            lazy_initialize(:info_panel) do
              @info_panel = Gtk::HBox.new(false, 0)
              @info_panel.border_width = 10
              @info_panel.pack_start(Gtk::Label.new("Runs:"), false, false, 0)
              @info_panel.pack_start(run_count_label, true, false, 0)
              @info_panel.pack_start(Gtk::Label.new("Assertions:"), false, false, 0)
              @info_panel.pack_start(assertion_count_label, true, false, 0)
              @info_panel.pack_start(Gtk::Label.new("Failures:"), false, false, 0)
              @info_panel.pack_start(failure_count_label, true, false, 0)
              @info_panel.pack_start(Gtk::Label.new("Errors:"), false, false, 0)
              @info_panel.pack_start(error_count_label, true, false, 0)
            end
          end # def info_panel
          private :info_panel

          def green_style
            lazy_initialize(:green_style) do
              @green_style = Gtk::Style.new
              @green_style.set_bg(Gtk::STATE_PRELIGHT, 0x0000, 0xFFFF, 0x0000)
            end
          end # def green_style
          private :green_style
          
          def red_style
            lazy_initialize(:red_style) do
              @red_style = Gtk::Style.new
              @red_style.set_bg(Gtk::STATE_PRELIGHT, 0xFFFF, 0x0000, 0x0000)
            end
          end # def red_style
          private :red_style
          
          def test_progress_bar
            lazy_initialize(:test_progress_bar) {
              @test_progress_bar = Gtk::ProgressBar.new
              @test_progress_bar.fraction = 0.0
              @test_progress_bar.
                set_size_request(@test_progress_bar.allocation.width,
                                 info_panel.size_request[1])
              @test_progress_bar.style = green_style
            }
          end # def test_progress_bar
          private :test_progress_bar
          
          def progress_panel
            lazy_initialize(:progress_panel) do
              @progress_panel = Gtk::HBox.new(false, 10)
              @progress_panel.border_width = 10
              @progress_panel.pack_start(test_progress_bar, true, true, 0)
            end
          end # def progress_panel

          def run_button
            lazy_initialize(:run_button) do
              @run_button = Gtk::Button.new("Run")
            end
          end # def run_button

          def suite_name_entry
            lazy_initialize(:suite_name_entry) do
              @suite_name_entry = Gtk::Entry.new
              @suite_name_entry.editable = false
            end
          end # def suite_name_entry
          private :suite_name_entry

          def suite_panel
            lazy_initialize(:suite_panel) do
              @suite_panel = Gtk::HBox.new(false, 10)
              @suite_panel.border_width = 10
              @suite_panel.pack_start(Gtk::Label.new("Suite:"), false, false, 0)
              @suite_panel.pack_start(suite_name_entry, true, true, 0)
              @suite_panel.pack_start(run_button, false, false, 0)
            end
          end # def suite_panel
          private :suite_panel

          def main_panel
            lazy_initialize(:main_panel) do
              @main_panel = Gtk::VBox.new(false, 0)
              @main_panel.pack_start(suite_panel, false, false, 0)
              @main_panel.pack_start(progress_panel, false, false, 0)
              @main_panel.pack_start(info_panel, false, false, 0)
              @main_panel.pack_start(list_panel, false, false, 0)
              @main_panel.pack_start(detail_panel, true, true, 0)
              @main_panel.pack_start(status_panel, false, false, 0)
            end
          end # def main_panel
          private :main_panel

          def main_window
            lazy_initialize(:main_window) do
              @main_window = Gtk::Window.new(Gtk::Window::TOPLEVEL)
              @main_window.set_title("Test::Unit TestRunner")
              @main_window.set_default_size(800, 600)
              @main_window.set_resizable(true)
              @main_window.add(main_panel)
            end
          end # def main_window
          private :main_window

          def setup_ui
            main_window.signal_connect("destroy", nil) { stop }
            main_window.show_all
            fault_list.selection.signal_connect("changed", nil) do
              |selection, data|
              if selection.selected then
                show_fault(fault_list.get_fault(selection.selected))
              else
                clear_fault
              end
            end
          end # def setup_ui
          private :setup_ui

          def output_status(string)
            status_entry.set_text(string)
          end # def output_status(string)
          private :output_status

          def finished(elapsed_time)
            test_progress_bar.fraction = 1.0
            output_status("Finished in #{elapsed_time} seconds")
          end # def finished(elapsed_time)
          private :finished

          def test_started(test_name)
            output_status("Running #{test_name}...")
          end # def test_started(test_name)
          private :test_started

          def started(result)
            @result = result
            output_status("Started...")
          end # def started(result)
          private :started

          def test_finished(result)
            test_progress_bar.fraction += 1.0 / @count
          end # def test_finished(result)

          def result_changed(result)
            run_count_label.label = result.run_count.to_s
            assertion_count_label.label = result.assertion_count.to_s
            failure_count_label.label = result.failure_count.to_s
            error_count_label.label = result.error_count.to_s
          end # def result_changed(result)
          private :result_changed

          def clear_fault
            raw_show_fault("")
          end # def clear_fault
          private :clear_fault

          def raw_show_fault(string)
            fault_detail_label.set_text(string)
            outer_detail_sub_panel.queue_resize
          end # def raw_show_fault(string)
          private :raw_show_fault

          def show_fault(fault)
            raw_show_fault(fault.long_display)
          end # def show_fault(fault)
          private :show_fault

          def add_fault(fault)
            if not @red then
              test_progress_bar.style = red_style
              @red = true
            end
            fault_list.add_fault(fault)
          end # def add_fault(fault)
          private :add_fault

          def reset_ui(count)
            test_progress_bar.style = green_style
            test_progress_bar.fraction = 0.0
            @count = count + 1
            @red = false

            run_count_label.set_text("0")
            assertion_count_label.set_text("0")
            failure_count_label.set_text("0")
            error_count_label.set_text("0")

            fault_list.clear
          end # def reset_ui(count)
          private :reset_ui

          def stop
            Gtk.main_quit
          end # def stop
          private :stop

          def run_test
            @runner.raise(@restart_signal)
          end
          private :run_test

          def start_ui
            @viewer.run
            running = false
            begin
              loop do
                if (running ^= true)
                  run_button.child.text = "Stop"
                  @mediator.run_suite
                else
                  run_button.child.text = "Run"
                  @viewer.join
                  break
                end
              end
            rescue @restart_signal
              retry
            rescue
            end
          end # def start_ui
          private :start_ui

          def attach_to_mediator
            run_button.signal_connect("clicked", nil) { run_test }
            @mediator.add_listener(TestRunnerMediator::RESET, &method(:reset_ui))
            @mediator.add_listener(TestRunnerMediator::STARTED, &method(:started))
            @mediator.add_listener(TestRunnerMediator::FINISHED, &method(:finished))
            @mediator.add_listener(TestResult::FAULT, &method(:add_fault))
            @mediator.add_listener(TestResult::CHANGED, &method(:result_changed))
            @mediator.add_listener(TestCase::STARTED, &method(:test_started))
            @mediator.add_listener(TestCase::FINISHED, &method(:test_finished))
          end # def attach_to_mediator
          private :attach_to_mediator

          def setup_mediator
            @mediator = TestRunnerMediator.new(@suite)
            suite_name = @suite.to_s
            if @suite.kind_of?(Module) then
              suite_name = @suite.name
            end
            suite_name_entry.set_text(suite_name)
          end # def setup_mediator
          private :setup_mediator

          def start
            setup_mediator
            setup_ui
            attach_to_mediator
            start_ui
            @result
          end # def start

          def initialize(suite, output_level = NORMAL)
            if suite.respond_to?(:suite) then
              @suite = suite.suite
            else
              @suite = suite
            end
            @result = nil

            @runner = Thread.current
            @restart_signal = Class.new(Exception)
            @viewer = Thread.start do
              @runner.join rescue @runner.run
              Gtk.main
            end
            @viewer.join rescue nil # wait deadlock to handshake
          end # def initialize(suite)

        end # class TestRunner

      end # module GTK2
    end # module UI
  end # module Unit
end # module Test
