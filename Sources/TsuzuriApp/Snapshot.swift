import AppKit

extension NSView {
    /// 動作の確かめ用。中身を指定の倍率の PNG に写し取る(画面の録画の権限は要らない)。
    /// 画面の倍率に関係なく同じ細かさで写せるよう、絵の画素数を自分で決める
    func pngSnapshot(scale: CGFloat = 2) -> Data? {
        let size = bounds.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ) else { return nil }
        rep.size = size
        cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
