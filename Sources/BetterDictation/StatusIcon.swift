import AppKit

/// 菜单栏图标：字母 BT + 录音图标，合成一枚 template image。
///
/// 对齐策略：先把内容画到离屏位图，扫描 alpha 得到**真实墨迹包围盒**，
/// 再按包围盒裁剪。这样字体侧边距、SF Symbol 内建留白都不会变成
/// 单侧空白 —— 系统把图片居中放进按钮时，视觉上就是正中。
enum StatusIcon {

    private static var cache: [DictationController.State: NSImage] = [:]

    static func image(for state: DictationController.State) -> NSImage {
        if let cached = cache[state] { return cached }
        let image = make(state)
        cache[state] = image
        return image
    }

    private static func make(_ state: DictationController.State) -> NSImage {
        let font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let letter = "BT" as NSString
        let letterWidth = letter.size(withAttributes: attributes).width

        let symbolName: String = {
            switch state {
            case .idle: return "mic"
            case .listening: return "mic.fill"
            case .finishing: return "waveform"
            }
        }()
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)

        let micHeight: CGFloat = 12
        let micWidth = symbol.map { max(9, $0.size.width * (micHeight / max($0.size.height, 1))) } ?? 9
        let gap: CGFloat = 1
        let inset: CGFloat = 4          // 画布留白，保证墨迹不会被裁到边界上
        let canvasWidth = ceil(letterWidth + gap + micWidth) + inset * 2
        let canvasHeight: CGFloat = 26
        let scale: CGFloat = 4

        let pixelWidth = Int(canvasWidth * scale)
        let pixelHeight = Int(canvasHeight * scale)
        let bytesPerRow = pixelWidth * 4
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bytesPerRow * pixelHeight, alignment: 4)
        memset(buffer, 0, bytesPerRow * pixelHeight)
        defer { buffer.deallocate() }

        guard let context = CGContext(
            data: buffer,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return fallbackSymbol(symbolName) }

        context.scaleBy(x: scale, y: scale)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        // cap 高度对齐到垂直中心（文本绘制原点含 descender 留白）
        let baseline = canvasHeight / 2 - font.capHeight / 2
        letter.draw(at: NSPoint(x: inset, y: baseline + font.descender), withAttributes: attributes)
        if let symbol {
            symbol.draw(in: NSRect(x: inset + letterWidth + gap,
                                   y: canvasHeight / 2 - micHeight / 2,
                                   width: micWidth,
                                   height: micHeight))
        }

        NSGraphicsContext.restoreGraphicsState()

        // 扫描 alpha 求墨迹包围盒（位图行序为自上而下，与 CGImage 裁剪坐标一致）
        let pixels = buffer.bindMemory(to: UInt8.self, capacity: bytesPerRow * pixelHeight)
        var minX = pixelWidth, maxX = -1, minY = pixelHeight, maxY = -1
        for y in 0 ..< pixelHeight {
            let row = y * bytesPerRow
            for x in 0 ..< pixelWidth where pixels[row + x * 4 + 3] > 80 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY,
              let full = context.makeImage()?.cropping(to: CGRect(
                  x: minX, y: minY,
                  width: maxX - minX + 1,
                  height: maxY - minY + 1
              ))
        else { return fallbackSymbol(symbolName) }

        let image = NSImage(cgImage: full, size: NSSize(
            width: CGFloat(full.width) / scale,
            height: CGFloat(full.height) / scale
        ))
        image.isTemplate = true
        return image
    }

    private static func fallbackSymbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "BetterDictation")
            ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        return image
    }
}
