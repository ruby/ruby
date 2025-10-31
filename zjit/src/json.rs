//! Single file JSON serializer for iongraph output of ZJIT HIR.

use std::{fmt, io::{self, BufWriter, Write}};

pub trait Serializable {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()>;
}

/// `Serializer` manages buffered writing to the sink of type `W`.
/// `needs_comma` is used to manage internal state.
pub struct Serializer<W: Write> {
    writer: BufWriter<W>,
    needs_comma: bool,
}

/// JSON's native null type.
pub struct JsonNull;

/// Convenience type for a result in JSON serialization.
pub type JsonResult<W> = std::result::Result<W, JsonError>;

#[derive(Debug)]
pub enum JsonError {
    /// Wrapper for a standard `io::Error`.
    IoError(io::Error),
    /// On attempting to serialize an invalid `f32` or `f64`.
    /// Stores invalid values as 64 bit float.
    FloatError(f64),
}

impl From<io::Error> for JsonError {
    fn from(err: io::Error) -> Self {
        JsonError::IoError(err)
    }
}

impl fmt::Display for JsonError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            JsonError::FloatError(v) => write!(f, "Cannot serialize float {}", v),
            JsonError::IoError(e) => write!(f, "{}", e),
        }
    }
}

impl std::error::Error for JsonError  {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            JsonError::IoError(e) => Some(e),
            JsonError::FloatError(_) => None,
        }
    }
}

impl<W: Write> Serializer<W> {
    pub fn new(writer: W) -> Self {
        Self {
            writer: BufWriter::new(writer),
            needs_comma: false,
        }
    }

    pub fn into_inner(self) -> JsonResult<W> {
        self.writer
            .into_inner()
            .map_err(|e| JsonError::IoError(e.into_error()))
    }

    pub fn write_str(&mut self, s: &str) -> JsonResult<()> {
        self.writer.write_all(b"\"")?;

        for ch in s.escape_debug() {
            write!(self.writer, "{}", ch)?;
        }

        self.writer.write_all(b"\"")?;
        Ok(())
    }

    pub fn write_array<S: Serializable>(&mut self, items: &[S]) -> JsonResult<()> {
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

    pub fn write_object<F>(&mut self, f: F) -> JsonResult<()>
    where
        F: FnOnce(&mut Self) -> JsonResult<()>,
    {
        self.writer.write_all(b"{")?;
        let prev_comma = self.needs_comma;
        self.needs_comma = false;
        f(self)?;
        self.needs_comma = prev_comma;
        self.writer.write_all(b"}")?;
        Ok(())
    }

    pub fn field<S: Serializable>(&mut self, key: &str, value: &S) -> JsonResult<()> {
        if self.needs_comma {
            self.writer.write_all(b", ")?;
        }
        self.needs_comma = true;

        self.write_str(key)?;
        self.writer.write_all(b": ")?;
        value.serialize(self)?;
        Ok(())
    }

    pub fn field_object<F>(&mut self, key: &str, f: F) -> JsonResult<()>
    where
        F: FnOnce(&mut Self) -> JsonResult<()>,
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
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()> {
        serializer.write_str(self)
    }
}

impl<S: Serializable> Serializable for Vec<S> {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()> {
        serializer.write_array(self)
    }
}

impl<S: Serializable> Serializable for [S] {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()> {
        serializer.write_array(self)
    }
}

impl<S: Serializable, const N: usize> Serializable for [S; N] {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()> {
        serializer.write_array(self)
    }
}

impl Serializable for &str {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()> {
        serializer.write_str(self)
    }
}

macro_rules! impl_serializable_int {
    ($($ty:ty),* $(,)?) => {
        $(
            impl Serializable for $ty {
                fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()> {
                    write!(serializer.writer, "{}", self)?;
                    Ok(())
                }
            }
        )*
    };
}

impl_serializable_int! {
    i8, i16, i32, i64, i128, isize,
    u8, u16, u32, u64, u128, usize,
}

impl Serializable for f64 {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()> {
        if matches!(self, &f64::INFINITY | &f64::NEG_INFINITY) || self.is_nan() {
            Err(JsonError::FloatError(*self))
        } else {
            write!(serializer.writer, "{}", self)?;
            Ok(())
        }
    }
}

impl Serializable for f32 {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()> {
        if matches!(self, &f32::INFINITY | &f32::NEG_INFINITY) || self.is_nan() {
            Err(JsonError::FloatError((*self).into()))
        } else {
            write!(serializer.writer, "{}", self)?;
            Ok(())
        }
    }
}

impl Serializable for bool {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()> {
        write!(serializer.writer, "{}", self)?;
        Ok(())
    }
}

impl Serializable for JsonNull {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()> {
        write!(serializer.writer, "null")?;
        Ok(())
    }
}

impl<T: Serializable + ?Sized> Serializable for &T {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()> {
        (*self).serialize(serializer)
    }
}

impl<S: Serializable> Serializable for Option<S> {
    fn serialize<W: Write>(&self, serializer: &mut Serializer<W>) -> JsonResult<()> {
        match self {
            Some(v) => v.serialize(serializer),
            None => JsonNull.serialize(serializer),
        }
    }
}
