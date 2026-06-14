/// 所有持久化檔案（metadata.json、live_segments.jsonl、manual_markers.jsonl、
/// audio/manifest.json）共用的 schema 版本。格式變更時遞增，讀取端據此遷移。
public enum SchemaVersion {
    public static let current = 2
}
