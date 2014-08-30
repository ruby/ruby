module SimpleCov::ArrayMergeHelper
  # Merges an array of coverage results with self
  def merge_resultset(array)
    new_array = []

    self.each_with_index do |element, i|
      new_array[i] = element
    end

    array.each_with_index do |element, i|
      if element.nil? and new_array[i].nil?
        new_array[i] = nil
      else
        local_value = element || 0
        other_value = new_array[i] || 0
        new_array[i] = local_value + other_value
      end
    end
    new_array
  end
end

module SimpleCov::HashMergeHelper
  # Merges the given Coverage.result hash with self
  def merge_resultset(hash)
    new_resultset = {}
    (self.keys + hash.keys).each do |filename|
      new_resultset[filename] = []
    end

    new_resultset.each do |filename, data|
      new_resultset[filename] = (self[filename] || []).merge_resultset(hash[filename] || [])
    end
    new_resultset
  end
end

Array.send :include, SimpleCov::ArrayMergeHelper
Hash.send :include, SimpleCov::HashMergeHelper
