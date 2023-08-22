import argparse
import textwrap

# usage: [-h] [-a | --all | --no-all] [-s STACK_SIZE] [uplevel]
#
# Dump a control frame
#
# positional arguments:
#   uplevel               CFP offset from the stack top
#
# options:
#   -h, --help            show this help message and exit
#   -a, --all, --no-all   dump all frames
#   -s STACK_SIZE, --stack-size STACK_SIZE
#                         override stack_size (useful for JIT frames)
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

        self.parser = argparse.ArgumentParser(description='Dump a control frame')
        self.parser.add_argument('uplevel', type=int, nargs='?', default=0, help='CFP offset from the stack top')
        self.parser.add_argument('-a', '--all', action=argparse.BooleanOptionalAction, help='dump all frames')
        self.parser.add_argument('-s', '--stack-size', type=int, help='override stack_size (useful for JIT frames)')

    def invoke(self, args, from_tty):
        try:
            args = self.parser.parse_args(args.split())
        except SystemExit:
            return
        cfp = f'(ruby_current_ec->cfp + ({args.uplevel}))'
        end_cfp = self.get_int('ruby_current_ec->vm_stack + ruby_current_ec->vm_stack_size')
        cfp_index = int((end_cfp - self.get_int(cfp) - 1) / self.get_int('sizeof(rb_control_frame_t)'))

        if args.all:
            cfp_count = int((end_cfp - self.get_int('ruby_current_ec->cfp')) / self.get_int('sizeof(rb_control_frame_t)')) - 1 # exclude dummy CFP
            for i in range(cfp_count):
                print('-' * 80)
                self.invoke(str(cfp_count - i - 1), from_tty)
            return

        print('CFP (addr=0x{:x}, index={}):'.format(self.get_int(cfp), cfp_index))
        gdb.execute(f'p *({cfp})')
        print()

        if self.get_int(f'{cfp}->iseq'):
            local_size = self.get_int(f'{cfp}->iseq->body->local_table_size - {cfp}->iseq->body->param.size')
            param_size = self.get_int(f'{cfp}->iseq->body->param.size')

            if local_size:
                print(f'Params (size={param_size}):')
                for i in range(-3 - local_size - param_size, -3 - local_size):
                    self.print_stack(cfp, i, self.rp(cfp, i))
                print()

            if param_size:
                print(f'Locals (size={local_size}):')
                for i in range(-3 - local_size, -3):
                    self.print_stack(cfp, i, self.rp(cfp, i))
                print()

        print('Env:')
        self.print_env(cfp, -3, self.rp_env(cfp, -3))
        self.print_env(cfp, -2, self.specval(cfp, -2))
        self.print_env(cfp, -1, self.frame_types(cfp, -1))
        print()

        # We can't calculate BP for the first frame.
        # vm_base_ptr doesn't work for C frames either.
        if cfp_index > 0 and self.get_int(f'{cfp}->iseq'):
            if args.stack_size is not None:
                stack_size = args.stack_size
            else:
                stack_size = int((self.get_int(f'{cfp}->sp') - self.get_int(f'vm_base_ptr({cfp})')) / 8)
            print(f'Stack (size={stack_size}):')
            for i in range(0, stack_size):
                self.print_stack(cfp, i, self.rp(cfp, i))
            print(self.regs(cfp, stack_size))

    def print_env(self, cfp, bp_index, content):
        ep_index = bp_index + 1
        address = self.get_int(f'((rb_control_frame_t *){cfp})->ep + {ep_index}')
        value = self.get_env(cfp, bp_index)
        regs = self.regs(cfp, bp_index)
        if content:
            content = textwrap.indent(content, ' ' * 3).lstrip() # Leave the regs column empty
            content = f'{content} '
        print('{:2} 0x{:x} [{}] {}(0x{:x})'.format(regs, address, bp_index, content, value))

    def print_stack(self, cfp, bp_index, content):
        address = self.get_int(f'vm_base_ptr({cfp}) + {bp_index}')
        value = self.get_value(cfp, bp_index)
        regs = self.regs(cfp, bp_index)
        if content:
            content = textwrap.indent(content, ' ' * 3).lstrip() # Leave the regs column empty
            content = f'{content} '
        print('{:2} 0x{:x} [{}] {}(0x{:x})'.format(regs, address, bp_index, content, value))

    def regs(self, cfp, bp_index):
        address = self.get_int(f'vm_base_ptr({cfp}) + {bp_index}')
        regs = []
        for reg, field in { 'EP': 'ep', 'SP': 'sp' }.items():
            if address == self.get_int(f'{cfp}->{field}'):
                regs.append(reg)
        return ' '.join(regs)

    def rp(self, cfp, bp_index):
        value = self.get_value(cfp, bp_index)
        return self.get_string(f'rp {value}').rstrip()

    def rp_env(self, cfp, bp_index):
        value = self.get_env(cfp, bp_index)
        return self.get_string(f'rp {value}').rstrip()

    # specval: block_handler or previous EP
    def specval(self, cfp, bp_index):
        value = self.get_env(cfp, bp_index)
        if value == 0:
            return 'VM_BLOCK_HANDLER_NONE'
        if value == self.get_int('rb_block_param_proxy'):
            return 'rb_block_param_proxy'
        return ''

    def frame_types(self, cfp, bp_index):
        types = []
        value = self.get_env(cfp, bp_index)

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

    def get_env(self, cfp, bp_index):
        ep_index = bp_index + 1
        return self.get_int(f'((rb_control_frame_t *){cfp})->ep[{ep_index}]')

    def get_value(self, cfp, bp_index):
        return self.get_int(f'vm_base_ptr({cfp})[{bp_index}]')

    def get_int(self, expr):
        return int(self.get_string(f'printf "%ld", ({expr})'))

    def get_string(self, expr):
        return gdb.execute(expr, to_string=True)

CFP()
