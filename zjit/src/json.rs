//! Single file JSON serializer for iongraph output of ZJIT HIR.

use std::{
    fmt,
    io::{self, Write},
};

pub trait Jsonable {
    fn to_json(&self) -> Json;
}

#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Integer(isize),
    UnsignedInteger(usize),
    Floating(f64),
    String(String),
    Array(Vec<Json>),
    Object(Vec<(String, Json)>),
}

impl Json {
    /// Convenience method for constructing a JSON array.
    pub fn array<I, T>(iter: I) -> Self
    where
        I: IntoIterator<Item = T>,
        T: Into<Json>,
    {
        Json::Array(iter.into_iter().map(Into::into).collect())
    }

    pub fn empty_array() -> Self {
        Json::Array(Vec::new())
    }

    pub fn object() -> JsonObjectBuilder {
        JsonObjectBuilder::new()
    }

    pub fn marshal<W: Write>(&self, writer: &mut W) -> JsonResult<()> {
        match self {
            Json::Null => writer.write_all(b"null"),
            Json::Bool(b) => writer.write_all(if *b { b"true" } else { b"false" }),
            Json::Integer(i) => write!(writer, "{i}"),
            Json::UnsignedInteger(u) => write!(writer, "{u}"),
            Json::Floating(f) => write!(writer, "{f}"),
            Json::String(s) => return Self::write_str(writer, s),
            Json::Array(jsons) => return Self::write_array(writer, jsons),
            Json::Object(map) => return Self::write_object(writer, map),
        }?;
        Ok(())
    }

    pub fn write_str<W: Write>(writer: &mut W, s: &str) -> JsonResult<()> {
        writer.write_all(b"\"")?;

        for ch in s.chars() {
            match ch {
                '"' => write!(writer, "\\\"")?,
                '\\' => write!(writer, "\\\\")?,
                // The following characters are control, but have a canonical representation.
                // https://datatracker.ietf.org/doc/html/rfc8259#section-7
                '\n' => write!(writer, "\\n")?,
                '\r' => write!(writer, "\\r")?,
                '\t' => write!(writer, "\\t")?,
                '\x08' => write!(writer, "\\b")?,
                '\x0C' => write!(writer, "\\f")?,
                ch if ch.is_control() => {
                    let code_point = ch as u32;
                    write!(writer, "\\u{code_point:04X}")?
                }
                _ => write!(writer, "{ch}")?,
            };
        }

        writer.write_all(b"\"")?;
        Ok(())
    }

    pub fn write_array<W: Write>(writer: &mut W, jsons: &[Json]) -> JsonResult<()> {
        writer.write_all(b"[")?;
        let mut prefix = "";
        for item in jsons {
            write!(writer, "{prefix}")?;
            item.marshal(writer)?;
            prefix = ", ";
        }
        writer.write_all(b"]")?;
        Ok(())
    }

    pub fn write_object<W: Write>(writer: &mut W, pairs: &[(String, Json)]) -> JsonResult<()> {
        writer.write_all(b"{")?;
        let mut prefix = "";
        for (k, v) in pairs {
            // Escape the keys, despite not being `Json::String` objects.
            write!(writer, "{prefix}")?;
            Self::write_str(writer, k)?;
            writer.write_all(b":")?;
            v.marshal(writer)?;
            prefix = ", ";
        }
        writer.write_all(b"}")?;
        Ok(())
    }
}

impl std::fmt::Display for Json {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let mut buf = Vec::new();
        self.marshal(&mut buf).map_err(|_| std::fmt::Error)?;
        let s = String::from_utf8(buf).map_err(|_| std::fmt::Error)?;
        write!(f, "{s}")
    }
}

pub struct JsonObjectBuilder {
    pairs: Vec<(String, Json)>,
}

impl JsonObjectBuilder {
    pub fn new() -> Self {
        Self { pairs: Vec::new() }
    }

    pub fn insert<K, V>(mut self, key: K, value: V) -> Self
    where
        K: Into<String>,
        V: Into<Json>,
    {
        self.pairs.push((key.into(), value.into()));
        self
    }

    pub fn build(self) -> Json {
        Json::Object(self.pairs)
    }
}

impl From<&str> for Json {
    fn from(s: &str) -> Json {
        Json::String(s.to_string())
    }
}

impl From<String> for Json {
    fn from(s: String) -> Json {
        Json::String(s)
    }
}

impl From<i32> for Json {
    fn from(i: i32) -> Json {
        Json::Integer(i as isize)
    }
}

impl From<i64> for Json {
    fn from(i: i64) -> Json {
        Json::Integer(i as isize)
    }
}

impl From<u32> for Json {
    fn from(u: u32) -> Json {
        Json::UnsignedInteger(u as usize)
    }
}

impl From<u64> for Json {
    fn from(u: u64) -> Json {
        Json::UnsignedInteger(u as usize)
    }
}

impl From<usize> for Json {
    fn from(u: usize) -> Json {
        Json::UnsignedInteger(u)
    }
}

impl From<bool> for Json {
    fn from(b: bool) -> Json {
        Json::Bool(b)
    }
}

impl TryFrom<f64> for Json {
    type Error = JsonError;
    fn try_from(f: f64) -> Result<Self, Self::Error> {
        if f.is_finite() {
            Ok(Json::Floating(f))
        } else {
            Err(JsonError::FloatError(f))
        }
    }
}

impl<T: Into<Json>> From<Vec<T>> for Json {
    fn from(v: Vec<T>) -> Json {
        Json::Array(v.into_iter().map(|item| item.into()).collect())
    }
}

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
            JsonError::FloatError(v) => write!(f, "Cannot serialize float {v}"),
            JsonError::IoError(e) => write!(f, "{e}"),
        }
    }
}

impl std::error::Error for JsonError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            JsonError::IoError(e) => Some(e),
            JsonError::FloatError(_) => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use insta::assert_snapshot;

    fn marshal_to_string(json: &Json) -> String {
        let mut buf = Vec::new();
        json.marshal(&mut buf).unwrap();
        String::from_utf8(buf).unwrap()
    }

    #[test]
    fn test_null() {
        let json = Json::Null;
        assert_snapshot!(marshal_to_string(&json), @"null");
    }

    #[test]
    fn test_bool() {
        let json: Json = true.into();
        assert_snapshot!(marshal_to_string(&json), @"true");
        let json: Json = false.into();
        assert_snapshot!(marshal_to_string(&json), @"false");
    }

    #[test]
    fn test_integer_positive() {
        let json: Json = 42.into();
        assert_snapshot!(marshal_to_string(&json), @"42");
    }

    #[test]
    fn test_integer_negative() {
        let json: Json = (-123).into();
        assert_snapshot!(marshal_to_string(&json), @"-123");
    }

    #[test]
    fn test_integer_zero() {
        let json: Json = 0.into();
        assert_snapshot!(marshal_to_string(&json), @"0");
    }

    #[test]
    fn test_floating() {
        let json = 2.14159.try_into();
        assert!(json.is_ok());
        let json = json.unwrap();
        assert_snapshot!(marshal_to_string(&json), @"2.14159");
    }

    #[test]
    fn test_floating_negative() {
        let json = (-2.5).try_into();
        assert!(json.is_ok());
        let json = json.unwrap();
        assert_snapshot!(marshal_to_string(&json), @"-2.5");
    }

    #[test]
    fn test_floating_error() {
        let json: Result<Json, JsonError> = f64::NAN.try_into();
        assert!(matches!(json, Err(JsonError::FloatError(_))));

        let json: Result<Json, JsonError> = f64::INFINITY.try_into();
        assert!(matches!(json, Err(JsonError::FloatError(_))));

        let json: Result<Json, JsonError> = f64::NEG_INFINITY.try_into();
        assert!(matches!(json, Err(JsonError::FloatError(_))));
    }

    #[test]
    fn test_string_simple() {
        let json: Json = "hello".into();
        assert_snapshot!(marshal_to_string(&json), @r#""hello""#);
    }

    #[test]
    fn test_string_empty() {
        let json: Json = "".into();
        assert_snapshot!(marshal_to_string(&json), @r#""""#);
    }

    #[test]
    fn test_string_with_quotes() {
        let json: Json = r#"hello "world""#.into();
        assert_snapshot!(marshal_to_string(&json), @r#""hello \"world\"""#);
    }

    #[test]
    fn test_string_with_backslash() {
        let json: Json = r"path\to\file".into();
        assert_snapshot!(marshal_to_string(&json), @r#""path\\to\\file""#);
    }

    #[test]
    fn test_string_with_slash() {
        let json: Json = "path/to/file".into();
        assert_snapshot!(marshal_to_string(&json), @r#""path/to/file""#);
    }

    #[test]
    fn test_string_with_newline() {
        let json: Json = "line1\nline2".into();
        assert_snapshot!(marshal_to_string(&json), @r#""line1\nline2""#);
    }

    #[test]
    fn test_string_with_carriage_return() {
        let json: Json = "line1\rline2".into();
        assert_snapshot!(marshal_to_string(&json), @r#""line1\rline2""#);
    }

    #[test]
    fn test_string_with_tab() {
        let json: Json = "col1\tcol2".into();
        assert_snapshot!(marshal_to_string(&json), @r#""col1\tcol2""#);
    }

    #[test]
    fn test_string_with_backspace() {
        let json: Json = "text\x08back".into();
        assert_snapshot!(marshal_to_string(&json), @r#""text\bback""#);
    }

    #[test]
    fn test_string_with_form_feed() {
        let json: Json = "page\x0Cnew".into();
        assert_snapshot!(marshal_to_string(&json), @r#""page\fnew""#);
    }

    #[test]
    fn test_string_with_control_chars() {
        let json: Json = "test\x01\x02\x03".into();
        assert_snapshot!(marshal_to_string(&json), @r#""test\u0001\u0002\u0003""#);
    }

    #[test]
    fn test_string_with_all_escapes() {
        let json: Json = "\"\\/\n\r\t\x08\x0C".into();
        assert_snapshot!(marshal_to_string(&json), @r#""\"\\/\n\r\t\b\f""#);
    }

    #[test]
    fn test_array_empty() {
        let json: Json = Vec::<i32>::new().into();
        assert_snapshot!(marshal_to_string(&json), @"[]");
    }

    #[test]
    fn test_array_single_element() {
        let json: Json = vec![42].into();
        assert_snapshot!(marshal_to_string(&json), @"[42]");
    }

    #[test]
    fn test_array_multiple_elements() {
        let json: Json = vec![1, 2, 3].into();
        assert_snapshot!(marshal_to_string(&json), @"[1, 2, 3]");
    }

    #[test]
    fn test_array_mixed_types() {
        let json = Json::Array(vec![
            Json::Null,
            true.into(),
            42.into(),
            3.134.try_into().unwrap(),
            "hello".into(),
        ]);
        assert_snapshot!(marshal_to_string(&json), @r#"[null, true, 42, 3.134, "hello"]"#);
    }

    #[test]
    fn test_array_nested() {
        let json = Json::Array(vec![1.into(), vec![2, 3].into(), 4.into()]);
        assert_snapshot!(marshal_to_string(&json), @"[1, [2, 3], 4]");
    }

    #[test]
    fn test_object_empty() {
        let json = Json::Object(vec![]);
        assert_snapshot!(marshal_to_string(&json), @"{}");
    }

    #[test]
    fn test_object_single_field() {
        let json = Json::Object(vec![("key".to_string(), "value".into())]);
        assert_snapshot!(marshal_to_string(&json), @r#"{"key":"value"}"#);
    }

    #[test]
    fn test_object_multiple_fields() {
        let json = Json::Object(vec![
            ("name".to_string(), "Alice".into()),
            ("age".to_string(), 30.into()),
            ("active".to_string(), true.into()),
        ]);
        assert_snapshot!(marshal_to_string(&json), @r#"{"name":"Alice", "age":30, "active":true}"#);
    }

    #[test]
    fn test_object_with_escaped_key() {
        let json = Json::Object(vec![("key\nwith\nnewlines".to_string(), 42.into())]);
        assert_snapshot!(marshal_to_string(&json), @r#"{"key\nwith\nnewlines":42}"#);
    }

    #[test]
    fn test_object_nested() {
        let inner = Json::Object(vec![("inner_key".to_string(), "inner_value".into())]);
        let json = Json::Object(vec![("outer_key".to_string(), inner)]);
        assert_snapshot!(marshal_to_string(&json), @r#"{"outer_key":{"inner_key":"inner_value"}}"#);
    }

    #[test]
    fn test_from_str() {
        let json: Json = "test string".into();
        assert_snapshot!(marshal_to_string(&json), @r#""test string""#);
    }

    #[test]
    fn test_from_i32() {
        let json: Json = 42i32.into();
        assert_snapshot!(marshal_to_string(&json), @"42");
    }

    #[test]
    fn test_from_i64() {
        let json: Json = 9223372036854775807i64.into();
        assert_snapshot!(marshal_to_string(&json), @"9223372036854775807");
    }

    #[test]
    fn test_from_u32() {
        let json: Json = 42u32.into();
        assert_snapshot!(marshal_to_string(&json), @"42");
    }

    #[test]
    fn test_from_u64() {
        let json: Json = 18446744073709551615u64.into();
        assert_snapshot!(marshal_to_string(&json), @"18446744073709551615");
    }

    #[test]
    fn test_unsigned_integer_zero() {
        let json: Json = 0u64.into();
        assert_snapshot!(marshal_to_string(&json), @"0");
    }

    #[test]
    fn test_from_bool() {
        let json_true: Json = true.into();
        let json_false: Json = false.into();
        assert_snapshot!(marshal_to_string(&json_true), @"true");
        assert_snapshot!(marshal_to_string(&json_false), @"false");
    }

    #[test]
    fn test_from_vec() {
        let json: Json = vec![1i32, 2i32, 3i32].into();
        assert_snapshot!(marshal_to_string(&json), @"[1, 2, 3]");
    }

    #[test]
    fn test_from_vec_strings() {
        let json: Json = vec!["a", "b", "c"].into();
        assert_snapshot!(marshal_to_string(&json), @r#"["a", "b", "c"]"#);
    }

    #[test]
    fn test_complex_nested_structure() {
        let settings = Json::Object(vec![
            ("notifications".to_string(), true.into()),
            ("theme".to_string(), "dark".into()),
        ]);

        let json = Json::Object(vec![
            ("id".to_string(), 1.into()),
            ("name".to_string(), "Alice".into()),
            ("tags".to_string(), vec!["admin", "user"].into()),
            ("settings".to_string(), settings),
        ]);
        assert_snapshot!(marshal_to_string(&json), @r#"{"id":1, "name":"Alice", "tags":["admin", "user"], "settings":{"notifications":true, "theme":"dark"}}"#);
    }

    #[test]
    fn test_deeply_nested_arrays() {
        let json = Json::Array(vec![
            Json::Array(vec![vec![1, 2].into(), 3.into()]),
            4.into(),
        ]);
        assert_snapshot!(marshal_to_string(&json), @"[[[1, 2], 3], 4]");
    }

    #[test]
    fn test_unicode_string() {
        let json: Json = "兵马俑".into();
        assert_snapshot!(marshal_to_string(&json), @r#""兵马俑""#);
    }

    #[test]
    fn test_json_array_convenience() {
        let json = Json::array(vec![1, 2, 3]);
        assert_snapshot!(marshal_to_string(&json), @"[1, 2, 3]");
    }

    #[test]
    fn test_json_array_from_iterator() {
        let json = Json::array([1, 2, 3].iter().map(|&x| x * 2));
        assert_snapshot!(marshal_to_string(&json), @"[2, 4, 6]");
    }

    #[test]
    fn test_json_empty_array() {
        let json = Json::empty_array();
        assert_snapshot!(marshal_to_string(&json), @"[]");
    }

    #[test]
    fn test_object_builder_empty() {
        let json = Json::object().build();
        assert_snapshot!(marshal_to_string(&json), @"{}");
    }

    #[test]
    fn test_object_builder_single_field() {
        let json = Json::object().insert("key", "value").build();
        assert_snapshot!(marshal_to_string(&json), @r#"{"key":"value"}"#);
    }

    #[test]
    fn test_object_builder_multiple_fields() {
        let json = Json::object()
            .insert("name", "Alice")
            .insert("age", 30)
            .insert("active", true)
            .build();
        assert_snapshot!(marshal_to_string(&json), @r#"{"name":"Alice", "age":30, "active":true}"#);
    }

    #[test]
    fn test_object_builder_with_nested_objects() {
        let inner = Json::object().insert("inner_key", "inner_value").build();
        let json = Json::object().insert("outer_key", inner).build();
        assert_snapshot!(marshal_to_string(&json), @r#"{"outer_key":{"inner_key":"inner_value"}}"#);
    }

    #[test]
    fn test_object_builder_with_array() {
        let json = Json::object().insert("items", vec![1, 2, 3]).build();
        assert_snapshot!(marshal_to_string(&json), @r#"{"items":[1, 2, 3]}"#);
    }

    #[test]
    fn test_display_trait() {
        let json = Json::object()
            .insert("name", "Bob")
            .insert("count", 42)
            .build();
        let display_output = format!("{}", json);
        assert_snapshot!(display_output, @r#"{"name":"Bob", "count":42}"#);
    }

    #[test]
    fn test_display_trait_array() {
        let json: Json = vec![1, 2, 3].into();
        let display_output = format!("{}", json);
        assert_snapshot!(display_output, @"[1, 2, 3]");
    }

    #[test]
    fn test_display_trait_string() {
        let json: Json = "test".into();
        let display_output = format!("{}", json);
        assert_snapshot!(display_output, @r#""test""#);
    }

    #[test]
    fn test_from_usize() {
        let json: Json = 123usize.into();
        assert_snapshot!(marshal_to_string(&json), @"123");
    }

    #[test]
    fn test_from_usize_large() {
        let json: Json = usize::MAX.into();
        let expected = format!("{}", usize::MAX);
        assert_eq!(marshal_to_string(&json), expected);
    }

    #[test]
    fn test_json_error_float_display() {
        let err = JsonError::FloatError(f64::NAN);
        let display_output = format!("{}", err);
        assert!(display_output.contains("Cannot serialize float"));
        assert!(display_output.contains("NaN"));
    }

    #[test]
    fn test_json_error_float_display_infinity() {
        let err = JsonError::FloatError(f64::INFINITY);
        let display_output = format!("{}", err);
        assert_snapshot!(display_output, @"Cannot serialize float inf");
    }

    #[test]
    fn test_json_error_io_display() {
        let io_err = io::Error::new(io::ErrorKind::WriteZero, "write error");
        let err = JsonError::IoError(io_err);
        let display_output = format!("{}", err);
        assert_snapshot!(display_output, @"write error");
    }

    #[test]
    fn test_io_error_during_marshal() {
        struct FailingWriter;
        impl Write for FailingWriter {
            fn write(&mut self, _buf: &[u8]) -> io::Result<usize> {
                Err(io::Error::other("simulated write failure"))
            }

            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }

        let json: Json = "test".into();
        let mut writer = FailingWriter;
        let result = json.marshal(&mut writer);
        assert!(result.is_err());
        assert!(matches!(result, Err(JsonError::IoError(_))));
    }

    #[test]
    fn test_clone_json() {
        let json1: Json = vec![1, 2, 3].into();
        let json2 = json1.clone();
        assert_eq!(json1, json2);
    }

    #[test]
    fn test_debug_json() {
        let json: Json = "test".into();
        let debug_output = format!("{:?}", json);
        assert!(debug_output.contains("String"));
        assert!(debug_output.contains("test"));
    }

    #[test]
    fn test_partial_eq_json() {
        let json1: Json = 42.into();
        let json2: Json = 42.into();
        let json3: Json = 43.into();
        assert_eq!(json1, json2);
        assert_ne!(json1, json3);
    }
}
