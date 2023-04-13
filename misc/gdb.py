import textwrap

# Usage:
#   cfp: Dump the current cfp
#   cfp 1: Dump the caller cfp
class CFP(gdb.Command):
    FRAME_MAGICS = [
        # frame types
        'VM_FRAME_MAGIC_METHOD',
        'VM_FRAME_MAGIC_BLOCK',
        'VM_FRAME_MAGIC_CLASS',
        'VM_FRAME_MAGIC_TOP',
        'VM_FRAME_MAGIC_CFUNC',
        'VM_FRAME_MAGIC_IFUNC',
        'VM_FRAME_MAGIC_EVAL',
        'VM_FRAME_MAGIC_RESCUE',
        'VM_FRAME_MAGIC_DUMMY',
    ]
    FRAME_FLAGS = [
        # frame flag
        'VM_FRAME_FLAG_FINISH',
        'VM_FRAME_FLAG_BMETHOD',
        'VM_FRAME_FLAG_CFRAME',
        'VM_FRAME_FLAG_LAMBDA',
        'VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM',
        'VM_FRAME_FLAG_CFRAME_KW',
        'VM_FRAME_FLAG_PASSED',
        # env flag
        'VM_ENV_FLAG_LOCAL',
        'VM_ENV_FLAG_ESCAPED',
        'VM_ENV_FLAG_WB_REQUIRED',
        'VM_ENV_FLAG_ISOLATED',
    ]

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

        if self.get_int(f'{cfp}->iseq'):
            local_size = self.get_int(f'{cfp}->iseq->body->local_table_size - {cfp}->iseq->body->param.size')
            param_size = self.get_int(f'{cfp}->iseq->body->param.size')
            print(f'Params (size={param_size}):')
            for i in range(-3 - local_size - param_size, -3 - local_size):
                self.print_stack(cfp, i, self.rp(cfp, i))
            print()

            print(f'Locals (size={local_size}):')
            for i in range(-3 - local_size, -3):
                self.print_stack(cfp, i, self.rp(cfp, i))
            print()

        print('Env:')
        self.print_stack(cfp, -3, self.rp(cfp, -3))
        self.print_stack(cfp, -2, self.specval(cfp, -2))
        self.print_stack(cfp, -1, self.frame_types(cfp, -1))
        print()

        stack_size = int((self.get_int(f'{cfp}->sp') - self.get_int(f'{cfp}->__bp__')) / 8)
        print(f'Stack (size={stack_size}):')
        for i in range(0, stack_size):
            self.print_stack(cfp, i, self.rp(cfp, i))
        print(self.regs(cfp, stack_size))

    def print_stack(self, cfp, bp_index, content):
        address = self.get_int(f'{cfp}->__bp__ + {bp_index}')
        value = self.get_value(cfp, bp_index)
        regs = self.regs(cfp, bp_index)
        if content:
            content = textwrap.indent(content, ' ' * 3).lstrip() # Leave the regs column empty
            content = f'{content} '
        print('{:2} 0x{:x} [{}] {}(0x{:x})'.format(regs, address, bp_index, content, value))

    def regs(self, cfp, bp_index):
        address = self.get_int(f'{cfp}->__bp__ + {bp_index}')
        regs = []
        for reg, field in { 'EP': 'ep', 'BP': '__bp__', 'SP': 'sp' }.items():
            if address == self.get_int(f'{cfp}->{field}'):
                regs.append(reg)
        return ' '.join(regs)

    def rp(self, cfp, bp_index):
        value = self.get_value(cfp, bp_index)
        return self.get_string(f'rp {value}').rstrip()

    # specval: block_handler or previous EP
    def specval(self, cfp, bp_index):
        value = self.get_value(cfp, bp_index)
        if value == 0:
            return 'VM_BLOCK_HANDLER_NONE'
        if value == self.get_int('rb_block_param_proxy'):
            return 'rb_block_param_proxy'
        return ''

    def frame_types(self, cfp, bp_index):
        types = []
        value = self.get_value(cfp, bp_index)

        magic_mask = self.get_int('VM_FRAME_MAGIC_MASK')
        for magic in self.FRAME_MAGICS:
            magic_value = self.get_int(magic)
            if value & magic_mask == magic_value:
                types.append(magic)

        for flag in self.FRAME_FLAGS:
            flag_value = self.get_int(flag)
            if value & flag_value:
                types.append(flag)

        return ' | '.join(types)

    def get_value(self, cfp, bp_index):
        return self.get_int(f'{cfp}->__bp__[{bp_index}]')

    def get_int(self, expr):
        return int(self.get_string(f'printf "%ld", ({expr})'))

    def get_string(self, expr):
        return gdb.execute(expr, to_string=True)

CFP()
