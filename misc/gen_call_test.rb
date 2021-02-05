NUM_LEVELS = 30
FNS_PER_LEVEL = 1000

$out = ""

def addln(str = "")
    $out << str << "\n"
end

NUM_LEVELS.times do |l_no|
    FNS_PER_LEVEL.times do |f_no|
        f_name = "fun_l#{l_no}_n#{f_no}"

        if l_no < NUM_LEVELS - 1
            callee_no = rand(0...FNS_PER_LEVEL)
            callee_name = "fun_l#{l_no+1}_n#{callee_no}"
        else
            callee_name = "inc"
        end

        addln("def #{f_name}()")
        addln("    #{callee_name}")
        addln("end")
        addln()
    end
end

addln("@a = 0")
addln("@b = 0")
addln("@c = 0")
addln("@d = 0")
addln("@count = 0")
addln("def inc()")
addln("    @count += 1")
addln("end")

# 100K times
addln("100000.times do")
    FNS_PER_LEVEL.times do |f_no|
        f_name = "fun_l0_n#{f_no}"
        addln("    #{f_name}")
    end
addln("end")

addln("puts @count")

puts($out)