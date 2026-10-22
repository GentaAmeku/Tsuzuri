// 生成した絵から、macOS のアプリのアイコン(AppIcon.icns)を作る。
// macOS 26 は、標準の形(角の丸い正方形)に収まらないアイコンを灰色の台座に入れるので、
// 絵の本体を切り出して 1024 の中の 824 の形に合わせて切り抜き、薄い影を付ける。
//
// 使い方: swift scripts/make-app-icon.swift <元の絵.png> <出力のフォルダ> [内側へ詰める割合(既定 0.015)]
//   出力のフォルダに AppIcon-1024.png・AppIcon.iconset・AppIcon.icns を置く
import AppKit
import SwiftUI

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("使い方: swift scripts/make-app-icon.swift <元の絵.png> <出力のフォルダ> [内側へ詰める割合]\n".data(using: .utf8)!)
    exit(1)
}
let source = URL(filePath: arguments[1])
let output = URL(filePath: arguments[2], directoryHint: .isDirectory)
let inset = arguments.count > 3 ? Double(arguments[3]) ?? 0.015 : 0.015

guard let image = NSImage(contentsOf: source),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("絵を読めません: \(source.path)\n".data(using: .utf8)!)
    exit(1)
}

/// 絵の本体の範囲。真ん中の横の線を左右の端から、真ん中の縦の線を上の端から見て、背景(四隅の色)と違う最初の画素を本体の縁とする。
/// 淡い色の本体でも縁を拾えるよう差は小さく見る。影は本体の下に出るので、下の縁は上の縁と幅から決める
func bodyRect(of image: CGImage) -> CGRect {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    // 画素の並びは上の行から(row 0 が絵の上の端)
    func pixel(_ x: Int, _ row: Int) -> (Int, Int, Int, Int) {
        let i = (row * width + x) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), Int(pixels[i + 3]))
    }
    let corner = pixel(2, 2)
    func differs(_ p: (Int, Int, Int, Int)) -> Bool {
        if corner.3 < 20 { return p.3 > 60 }
        return abs(p.0 - corner.0) + abs(p.1 - corner.1) + abs(p.2 - corner.2) > 24
    }
    let middleRow = height / 2, middleColumn = width / 2
    let left = (0..<width).first { differs(pixel($0, middleRow)) } ?? 0
    let right = (0..<width).reversed().first { differs(pixel($0, middleRow)) } ?? width - 1
    let top = (0..<height).first { differs(pixel(middleColumn, $0)) } ?? 0
    let side = right - left + 1
    // CGImage の切り出しは上が原点
    return CGRect(x: left, y: top, width: side, height: side)
}

var body = bodyRect(of: cgImage)
// 正方形にそろえ、内側へ少し詰めて、元の絵の角や縁の背景が入らないようにする
let side = min(body.width, body.height) * (1 - inset * 2)
body = CGRect(x: body.midX - side / 2, y: body.midY - side / 2, width: side, height: side)
guard let cropped = cgImage.cropping(to: body) else { exit(1) }
print("本体の範囲: \(body.integral)(元の大きさ \(cgImage.width)x\(cgImage.height))")

/// 1024 の中に 824 の形で置いた絵を描く
func render(size: Int) -> CGImage {
    let scale = CGFloat(size) / 1024
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: scale, y: scale)
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: rect).cgPath
    // 薄い影(下へ少しずらす)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.interpolationQuality = .high
    context.draw(cropped, in: rect)
    context.restoreGState()
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let fileManager = FileManager.default
try? fileManager.createDirectory(at: output, withIntermediateDirectories: true)
writePNG(render(size: 1024), to: output.appending(path: "AppIcon-1024.png"))
let iconset = output.appending(path: "AppIcon.iconset", directoryHint: .isDirectory)
try? fileManager.removeItem(at: iconset)
try! fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base), to: iconset.appending(path: "icon_\(base)x\(base).png"))
    writePNG(render(size: base * 2), to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
let process = Process()
process.executableURL = URL(filePath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appending(path: "AppIcon.icns").path]
try! process.run()
process.waitUntilExit()
print(process.terminationStatus == 0 ? "作った: \(output.appending(path: "AppIcon.icns").path)" : "iconutil が失敗しました")
