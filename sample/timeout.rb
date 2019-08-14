require 'timeout'

def progress(n = 5)
  n.times {|i| print i; STDOUT.flush; sleep 1}
  puts "never reach"
end

p Timeout.timeout(5) {
  45
}
p Timeout.timeout(5, Timeout::Error) {
  45
}
p Timeout.timeout(nil) {
  54
}
p Timeout.timeout(0) {
  54
}
begin
  Timeout.timeout(5) {progress}
rescue => e
  puts e.message
end
begin
  Timeout.timeout(3) {
    begin
      Timeout.timeout(5) {progress}
    rescue => e
      puts "never reach"
    end
  }
rescue => e
  puts e.message
end
class MyTimeout < StandardError
end
begin
  Timeout.timeout(2, MyTimeout) {progress}
rescue MyTimeout => e
  puts e.message
end
