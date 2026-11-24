//! Checked SSW1 IPC decoder. SNS/DU interpretation remains in the native domain.
use crate::model::{Node, NodeMetadata, Snapshot};
use anyhow::{Context, Result, ensure};
use std::collections::HashMap;
struct Reader<'a> {
    bytes: &'a [u8],
    offset: usize,
}
impl<'a> Reader<'a> {
    fn take(&mut self, count: usize) -> Result<&'a [u8]> {
        let end = self
            .offset
            .checked_add(count)
            .context("wire length overflow")?;
        let value = self.bytes.get(self.offset..end).context("truncated wire")?;
        self.offset = end;
        Ok(value)
    }
    fn u8(&mut self) -> Result<u8> {
        Ok(self.take(1)?[0])
    }
    fn u16(&mut self) -> Result<u16> {
        Ok(u16::from_le_bytes(self.take(2)?.try_into()?))
    }
    fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into()?))
    }
    fn u64(&mut self) -> Result<u64> {
        Ok(u64::from_le_bytes(self.take(8)?.try_into()?))
    }
    fn f64(&mut self) -> Result<f64> {
        let value = f64::from_bits(self.u64()?);
        ensure!(value.is_finite(), "nonfinite wire value");
        Ok(value)
    }
    fn string(&mut self) -> Result<String> {
        let count = self.u32()? as usize;
        Ok(std::str::from_utf8(self.take(count)?)?.to_owned())
    }
    fn optional_string(&mut self) -> Result<Option<String>> {
        let count = self.u32()?;
        if count == u32::MAX {
            return Ok(None);
        }
        Ok(Some(
            std::str::from_utf8(self.take(count as usize)?)?.to_owned(),
        ))
    }
    fn count(&mut self, minimum_bytes: usize) -> Result<usize> {
        let count = self.u32()? as usize;
        ensure!(
            count <= self.bytes.len().saturating_sub(self.offset) / minimum_bytes,
            "invalid wire count"
        );
        Ok(count)
    }
}
pub fn version(bytes: &[u8]) -> Result<Option<String>> {
    let mut reader = Reader { bytes, offset: 0 };
    ensure!(reader.take(4)? == b"SSW1", "unsupported wire magic");
    match reader.u16()? {
        1 => Ok(None),
        2 => {
            let value = reader.string()?;
            Ok(if value.is_empty() { None } else { Some(value) })
        }
        _ => anyhow::bail!("unsupported wire version"),
    }
}
pub fn decode(bytes: &[u8]) -> Result<Snapshot> {
    let mut reader = Reader { bytes, offset: 0 };
    ensure!(reader.take(4)? == b"SSW1", "unsupported wire magic");
    let schema = reader.u16()?;
    ensure!((1..=2).contains(&schema), "unsupported wire version");
    let wire_version = if schema == 2 {
        let value = reader.string()?;
        if value.is_empty() { None } else { Some(value) }
    } else {
        None
    };
    let count = reader.u32()? as usize;
    ensure!(
        count > 0 && count <= 20_000_000 && count <= bytes.len() / 67,
        "invalid wire node count"
    );
    let root = reader.string()?;
    let flags = reader.u8()?;
    ensure!(flags & !3 == 0, "invalid snapshot flags");
    let traversal = match reader.u8()? {
        0 => None,
        1 => Some("selectedVolume".into()),
        2 => Some("allVolumes".into()),
        _ => anyhow::bail!("invalid volume traversal"),
    };
    let files = usize::try_from(reader.u64()?)?;
    let folders = usize::try_from(reader.u64()?)?;
    let errors = usize::try_from(reader.u64()?)?;
    let excluded = usize::try_from(reader.u64()?)?;
    let elapsed = reader.f64()?;
    let volume_total = reader.u64()?;
    let volume_free = reader.u64()?;
    let issue_count = reader.count(4)?;
    ensure!(issue_count <= 500, "unbounded issue list");
    let mut issues = Vec::with_capacity(issue_count);
    for _ in 0..issue_count {
        issues.push(reader.string()?);
    }
    let tags_count = reader.count(5)?;
    ensure!(tags_count <= 20_000_000, "unbounded tags");
    let mut tags = HashMap::with_capacity(tags_count);
    for _ in 0..tags_count {
        let path = reader.string()?;
        let mask = reader.u8()?;
        ensure!(
            (1..=15).contains(&mask) && tags.insert(path, mask).is_none(),
            "invalid tags"
        );
    }
    let mut nodes = Vec::with_capacity(count);
    for id in 0..count {
        let parent = reader.u64()? as i64;
        let parent = if parent == -1 {
            None
        } else {
            Some(usize::try_from(parent)?)
        };
        let name = reader.string()?;
        let logical = reader.u64()?;
        let allocated = reader.u64()?;
        let attributes = reader.u32()?;
        let flags = reader.u8()?;
        ensure!(flags & !63 == 0, "invalid node flags");
        let modified = reader.f64()?;
        let created = reader.f64()?;
        let accessed = reader.f64()?;
        let native_type = reader.u8()?;
        let native_flags = reader.u8()?;
        let error = reader.optional_string()?.map(serde_json::Value::String);
        let children_count = reader.count(4)?;
        ensure!(children_count < count, "invalid child count");
        let mut children = Vec::with_capacity(children_count);
        for _ in 0..children_count {
            children.push(reader.u32()? as usize);
        }
        nodes.push(Node {
            id,
            parent,
            name,
            path: if id == 0 { root.clone() } else { String::new() },
            directory: flags & 1 != 0,
            boundary: flags & 2 != 0,
            logical,
            allocated,
            attributes,
            error,
            children,
            metadata: NodeMetadata {
                modified: Some(modified),
                created: if flags & 4 != 0 { Some(created) } else { None },
                accessed: if flags & 8 != 0 { Some(accessed) } else { None },
                native_type: if flags & 16 != 0 {
                    Some(native_type)
                } else {
                    None
                },
                native_flags: if flags & 32 != 0 {
                    Some(native_flags)
                } else {
                    None
                },
            },
        });
    }
    ensure!(reader.offset == bytes.len(), "trailing wire data");
    Ok(Snapshot {
        document: None,
        schema: 1,
        wire_version,
        root,
        cancelled: flags & 1 != 0,
        files,
        folders,
        errors,
        excluded,
        elapsed,
        volume_total,
        volume_free,
        is_volume_root: flags & 2 != 0,
        volume_traversal: traversal,
        nodes,
        tags,
        issues,
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn malformed_counts_and_truncated_headers_fail_before_allocation() {
        for input in [
            &b""[..],
            &b"SSW1"[..],
            &b"SSW1\x02\0\x01\0\0\0"[..],
            &b"SSW1\x01\0\xff\xff\xff\xff"[..],
        ] {
            assert!(decode(input).is_err());
        }
    }
}
