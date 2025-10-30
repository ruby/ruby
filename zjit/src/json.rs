//! Single file JSON serializer for iongraph output of ZJIT HIR.

use std::io::{self, Write};

pub trait Serializable {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> io::Result<()>;
}

pub struct Serializer<W: Write> {
    writer: W,
    needs_comma: bool,
}

/// JSON's native null type.
pub struct Null;

impl<W: Write> Serializer<W> {
    pub fn new(writer: W) -> Self {
        Self {
            writer,
            needs_comma: false,
        }
    }

    pub fn write_str(&mut self, s: &str) -> io::Result<()> {
        self.writer.write_all(b"\"")?;
        // todo: need to escape things I think
        self.writer.write_all(s.as_bytes())?;
        self.writer.write_all(b"\"")?;
        Ok(())
    }

    pub fn write_array<S: Serializable>(&mut self, items: &[S]) -> io::Result<()> {
        self.writer.write_all(b"[")?;
        for (i, item) in items.iter().enumerate() {
            item.serialize(self)?;
            if i < items.len() - 1 {
                self.writer.write_all(b", ")?;
            }
        }
        self.writer.write_all(b"]")?;
        Ok(())
    }

    pub fn write_object<F>(&mut self, f: F) -> io::Result<()>
    where
        F: FnOnce(&mut Self) -> io::Result<()>,
    {
        self.writer.write_all(b"{")?;
        let prev_comma = self.needs_comma;
        self.needs_comma = false;
        f(self)?;
        self.needs_comma = prev_comma;
        self.writer.write_all(b"}")?;
        Ok(())
    }

    pub fn field<S: Serializable>(&mut self, key: &str, value: &S) -> io::Result<()> {
        if self.needs_comma {
            self.writer.write_all(b", ")?;
        }
        self.needs_comma = true;

        self.write_str(key)?;
        self.writer.write_all(b": ")?;
        value.serialize(self)?;
        Ok(())
    }

    pub fn field_object<F>(&mut self, key: &str, f: F) -> io::Result<()>
    where
        F: FnOnce(&mut Self) -> io::Result<()>,
    {
        if self.needs_comma {
            self.writer.write_all(b", ")?;
        }
        self.needs_comma = true;

        self.write_str(key)?;
        self.writer.write_all(b": ")?;
        self.write_object(f)?;
        Ok(())
    }
}

impl Serializable for String {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> io::Result<()> {
        serializer.write_str(self)
    }
}

impl<S: Serializable> Serializable for Vec<S> {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> io::Result<()> {
        serializer.write_array(self)
    }
}

impl Serializable for &str {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> io::Result<()> {
        serializer.write_str(self)
    }
}

impl Serializable for i32 {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> io::Result<()> {
        write!(serializer.writer, "{}", self)
    }
}

impl Serializable for u32 {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> io::Result<()> {
        write!(serializer.writer, "{}", self)
    }
}

impl Serializable for f64 {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> io::Result<()> {
        write!(serializer.writer, "{}", self)
    }
}

impl Serializable for bool {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> io::Result<()> {
        write!(serializer.writer, "{}", self)
    }
}

impl Serializable for Null {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> io::Result<()> {
        write!(serializer.writer, "null")
    }
}
