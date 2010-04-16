# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/util/observable'

module Test
  module Unit
    module Util
      class TC_Observable < TestCase

        class TF_Observable
          include Observable
        end

        def setup
          @observable = TF_Observable.new
        end

        def test_simple_observation
          assert_raises(ArgumentError, "add_listener should throw an exception if no callback is supplied") do
            @observable.add_listener(:property, "a")
          end

          heard = false
          callback = proc { heard = true }
          assert_equal("a", @observable.add_listener(:property, "a", &callback), "add_listener should return the listener that was added")

          count = 0
          @observable.instance_eval do
            count = notify_listeners(:property)
          end
          assert_equal(1, count, "notify_listeners should have returned the number of listeners that were notified")
          assert(heard, "Should have heard the property changed")

          heard = false
          assert_equal(callback, @observable.remove_listener(:property, "a"), "remove_listener should return the callback")

          count = 1
          @observable.instance_eval do
            count = notify_listeners(:property)
          end
          assert_equal(0, count, "notify_listeners should have returned the number of listeners that were notified")
          assert(!heard, "Should not have heard the property change")
        end

        def test_value_observation
          value = nil
          @observable.add_listener(:property, "a") do |passed_value|
            value = passed_value
          end
          count = 0
          @observable.instance_eval do
            count = notify_listeners(:property, "stuff")
          end
          assert_equal(1, count, "Should have update the correct number of listeners")
          assert_equal("stuff", value, "Should have received the value as an argument to the listener")
        end

        def test_multiple_value_observation
          values = []
          @observable.add_listener(:property, "a") do |first_value, second_value|
            values = [first_value, second_value]
          end
          count = 0
          @observable.instance_eval do
            count = notify_listeners(:property, "stuff", "more stuff")
          end
          assert_equal(1, count, "Should have update the correct number of listeners")
          assert_equal(["stuff", "more stuff"], values, "Should have received the value as an argument to the listener")
        end

        def test_add_remove_with_default_listener
          assert_raises(ArgumentError, "add_listener should throw an exception if no callback is supplied") do
            @observable.add_listener(:property)
          end

          heard = false
          callback = proc { heard = true }
          assert_equal(callback, @observable.add_listener(:property, &callback), "add_listener should return the listener that was added")

          count = 0
          @observable.instance_eval do
            count = notify_listeners(:property)
          end
          assert_equal(1, count, "notify_listeners should have returned the number of listeners that were notified")
          assert(heard, "Should have heard the property changed")

          heard = false
          assert_equal(callback, @observable.remove_listener(:property, callback), "remove_listener should return the callback")

          count = 1
          @observable.instance_eval do
            count = notify_listeners(:property)
          end
          assert_equal(0, count, "notify_listeners should have returned the number of listeners that were notified")
          assert(!heard, "Should not have heard the property change")
        end
      end
    end
  end
end
