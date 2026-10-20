// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Tsuzuri",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "TsuzuriCore", targets: ["TsuzuriCore"]),
        .library(name: "TsuzuriEngines", targets: ["TsuzuriEngines"]),
        .library(name: "TsuzuriEvalKit", targets: ["TsuzuriEvalKit"]),
        .executable(name: "tsuzuri-eval", targets: ["TsuzuriEval"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "1.1.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        // 副作用の無い処理。テストの中心
        .target(name: "TsuzuriCore"),
        // 認識・キーチェーン・音声ファイルなど、OS や外部とやり取りする処理
        .target(name: "TsuzuriEngines", dependencies: ["TsuzuriCore"]),
        // 評価セットと結果の読み書き。tsuzuri-eval と Tools/Qwen3Eval が使う
        .target(name: "TsuzuriEvalKit", dependencies: ["TsuzuriCore", "TsuzuriEngines"]),
        .executableTarget(
            name: "TsuzuriEval",
            dependencies: [
                "TsuzuriCore",
                "TsuzuriEngines",
                "TsuzuriEvalKit",
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(name: "TsuzuriCoreTests", dependencies: ["TsuzuriCore"])
    ]
)
