use std::io::IsTerminal;

pub fn stdout_supports_colors() -> bool {
    std::io::stdout().is_terminal()
}

#[cfg_attr(not(feature = "disasm"), allow(dead_code))]
#[derive(Copy, Clone, Debug)]
pub struct TerminalColor {
    pub bold_begin: &'static str,
    pub bold_end: &'static str,
}

pub static TTY_TERMINAL_COLOR: TerminalColor = TerminalColor {
    bold_begin: "\x1b[1m",
    bold_end: "\x1b[22m",
};

pub static NON_TTY_TERMINAL_COLOR: TerminalColor = TerminalColor {
    bold_begin: "",
    bold_end: "",
};

/// Terminal escape codes for colors, font weight, etc. Only enabled if stdout is a TTY.
pub fn get_colors() -> &'static TerminalColor {
    if stdout_supports_colors() {
        &TTY_TERMINAL_COLOR
    } else {
        &NON_TTY_TERMINAL_COLOR
    }
}
