/// 版本号的**唯一来源**：改这里的 `marketing`，CI 与 `.app` 的 Info.plist 都从这里取值。
public enum AppVersion {

    /// 语义化版本。`scripts/version.sh` 会解析这一行，发布前手动修改。
    public static let marketing = "26.10.24"

    /// 显示用版本号
    public static var display: String { marketing }

    /// 形如 “v26.10.24”
    public static var tag: String { "v\(marketing)" }
}
