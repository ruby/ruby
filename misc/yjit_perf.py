import os
import sys
from collections import Counter, defaultdict
import os.path

sys.path.append(os.environ['PERF_EXEC_PATH'] + '/scripts/python/Perf-Trace-Util/lib/Perf/Trace')
from perf_trace_context import *
from EventClass import *

# Aggregating cycles per symbol and dso
total_cycles = 0
category_cycles = Counter()
detailed_category_cycles = defaultdict(Counter)
categories = set()

def truncate_symbol(symbol, max_length=50):
    """ Truncate the symbol name to a maximum length """
    return symbol if len(symbol) <= max_length else symbol[:max_length-3] + '...'

def categorize_symbol(dso, symbol):
    """ Categorize the symbol based on the defined criteria """
    if dso == 'sqlite3_native.so':
        return '[sqlite3]'
    elif 'SHA256' in symbol:
        return '[sha256]'
    elif symbol.startswith('[JIT] gen_send'):
        return '[JIT send]'
    elif symbol.startswith('[JIT]'):
        return '[JIT code]'
    elif '::' in symbol or symbol.startswith('yjit::') or symbol.startswith('_ZN4yjit'):
        return '[YJIT compile]'
    elif symbol.startswith('rb_vm_') or symbol.startswith('vm_') or symbol in {
        "rb_call0", "callable_method_entry_or_negative", "invoke_block_from_c_bh",
        "rb_funcallv_scope", "setup_parameters_complex", "rb_yield"}:
        return '[interpreter]'
    elif symbol.startswith('rb_hash_') or symbol.startswith('hash_'):
        return '[rb_hash_*]'
    elif symbol.startswith('rb_ary_') or symbol.startswith('ary_'):
        return '[rb_ary_*]'
    elif symbol.startswith('rb_str_') or symbol.startswith('str_'):
        return '[rb_str_*]'
    elif symbol.startswith('rb_sym') or symbol.startswith('sym_'):
        return '[rb_sym_*]'
    elif symbol.startswith('rb_st_') or symbol.startswith('st_'):
        return '[rb_st_*]'
    elif symbol.startswith('rb_ivar_') or 'shape' in symbol:
        return '[ivars]'
    elif 'match' in symbol or symbol.startswith('rb_reg') or symbol.startswith('onig'):
        return '[regexp]'
    elif 'alloc' in symbol or 'free' in symbol or 'gc' in symbol:
        return '[GC]'
    elif 'pthread' in symbol and 'lock' in symbol:
        return '[pthread lock]'
    else:
        return symbol  # Return the symbol itself for uncategorized symbols

def process_event(event):
    global total_cycles, category_cycles, detailed_category_cycles, categories

    sample = event["sample"]
    full_dso = event.get("dso", "Unknown_dso")
    dso = os.path.basename(full_dso)
    symbol = event.get("symbol", "[unknown]")
    cycles = sample["period"]
    total_cycles += cycles

    category = categorize_symbol(dso, symbol)
    category_cycles[category] += cycles
    detailed_category_cycles[category][(dso, symbol)] += cycles

    if category.startswith('[') and category.endswith(']'):
        categories.add(category)

def trace_end():
    if total_cycles == 0:
        return

    print("Aggregated Event Data:")
    print("{:<20} {:<50} {:>20} {:>15}".format("[dso]", "[symbol or category]", "[top-most cycle ratio]", "[num cycles]"))

    for category, cycles in category_cycles.most_common():
        ratio = (cycles / total_cycles) * 100
        dsos = {dso for dso, _ in detailed_category_cycles[category]}
        dso_display = next(iter(dsos)) if len(dsos) == 1 else "Multiple DSOs"
        print("{:<20} {:<50} {:>20.2f}% {:>15}".format(dso_display, truncate_symbol(category), ratio, cycles))

    # Category breakdown
    for category in categories:
        symbols = detailed_category_cycles[category]
        category_total = sum(symbols.values())
        category_ratio = (category_total / total_cycles) * 100
        print(f"\nCategory: {category} ({category_ratio:.2f}%)")
        print("{:<20} {:<50} {:>20} {:>15}".format("[dso]", "[symbol]", "[top-most cycle ratio]", "[num cycles]"))
        for (dso, symbol), cycles in symbols.most_common():
            symbol_ratio = (cycles / category_total) * 100
            print("{:<20} {:<50} {:>20.2f}% {:>15}".format(dso, truncate_symbol(symbol), symbol_ratio, cycles))
