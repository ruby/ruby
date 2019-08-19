# frozen_string_literal: true
require 'test/unit'
require 'fiddle'

class TestGCCompact < Test::Unit::TestCase
  if Fiddle::SIZEOF_LONG == Fiddle::SIZEOF_VOIDP
    def memory_location(obj)
      (Fiddle.dlwrap(obj) >> 1)
    end
  elsif Fiddle::SIZEOF_LONG_LONG == Fiddle::SIZEOF_VOIDP
    def memory_location(obj)
      (Fiddle.dlwrap(obj) >> 1) / 2
    end
  else
    raise "Not supported"
  end

  def assert_object_ids(list)
    same_count = list.find_all { |obj|
      memory_location(obj) == obj.object_id
    }.count
    list.count - same_count
  end

  def big_list
    1000.times.map { Object.new } # likely next to each other
  end

  # Find an object that's allocated in a slot that had a previous
  # tenant, and that tenant moved and is still alive
  def find_object_in_recycled_slot(addresses)
    new_object = nil

    loop do
      new_object = Object.new
      if addresses.include? memory_location(new_object)
        break
      end
    end

    new_object
  end

  def test_find_collided_object
    list_of_objects = big_list

    ids       = list_of_objects.map(&:object_id) # store id in map
    addresses = list_of_objects.map(&self.:memory_location)

    # All object ids should be equal
    assert_equal 0, assert_object_ids(list_of_objects) # should be 0

    GC.compact

    # Some should have moved
    assert_operator assert_object_ids(list_of_objects), :>, 0

    new_ids = list_of_objects.map(&:object_id)

    # Object ids should not change after compaction
    assert_equal ids, new_ids

    new_tenant = find_object_in_recycled_slot(addresses)
    assert new_tenant

    # This is the object that used to be in new_object's position
    previous_tenant = list_of_objects[addresses.index(memory_location(new_tenant))]

    assert_not_equal previous_tenant.object_id, new_tenant.object_id

    # Should be able to look up object by object_id
    assert_equal new_tenant, ObjectSpace._id2ref(new_tenant.object_id)

    # Should be able to look up object by object_id
    assert_equal previous_tenant, ObjectSpace._id2ref(previous_tenant.object_id)

    int = (new_tenant.object_id >> 1)
    # These two should be the same! but they are not :(
    assert_equal int, ObjectSpace._id2ref(int.object_id)
  end

  def test_many_collisions
    list_of_objects = big_list
    ids       = list_of_objects.map(&:object_id)
    addresses = list_of_objects.map(&self.:memory_location)

    GC.compact

    new_tenants = 10.times.map {
      find_object_in_recycled_slot(addresses)
    }

    assert_operator GC.stat(:object_id_collisions), :>, 0
  end
end
