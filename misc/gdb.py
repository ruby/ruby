# Usage:
#   cfp: Dump the current cfp
#   cfp + 1: Dump the caller cfp
class CFP(gdb.Command):
    def __init__(self):
        super(CFP, self).__init__('cfp', gdb.COMMAND_USER)

    def invoke(self, offset, from_tty):
        if not offset:
            offset = '0'
        cfp = f'(ruby_current_ec->cfp + ({offset}))'

        end_cfp = self.get_int('ruby_current_ec->vm_stack + ruby_current_ec->vm_stack_size')
        cfp_count = int((end_cfp - self.get_int('ruby_current_ec->cfp')) / self.get_int('sizeof(rb_control_frame_t)'))

        print('CFP (count={}, addr=0x{:x}):'.format(cfp_count, self.get_int(cfp)))
        gdb.execute(f'p *({cfp})')
        print()

        stack_size = int((self.get_int(f'{cfp}->sp') - self.get_int(f'{cfp}->__bp__')) / 8)
        print(f'Stack (size={stack_size}):')
        for i in range(0, stack_size):
            obj = self.get_int(f'{cfp}->__bp__[{i}]')
            rp = self.get_string(f'rp {obj}')
            print(f'[{i}] {rp}', end='')

    def get_int(self, expr):
        return int(self.get_string(f'printf "%ld", ({expr})'))

    def get_string(self, expr):
        return gdb.execute(expr, to_string=True)

CFP()
