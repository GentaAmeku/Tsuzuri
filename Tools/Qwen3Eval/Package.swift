// swift-tools-version: 6.2

import PackageDescription

// Qwen3-ASR の評価だけに使う。speech-swift は依存が大きい(MLX など)ので、本体のパッケージから分ける
let package = Package(
    name: "Qwen3Eval",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/soniqo/speech-swift", exact: "0.0.28")
    ],
    targets: [
        .executableTarget(
            name: "Qwen3Eval",
            dependencies: [
                .product(name: "TsuzuriCore", package: "Tsuzuri"),
                .product(name: "TsuzuriEngines", package: "Tsuzuri"),
                .product(name: "TsuzuriEvalKit", package: "Tsuzuri"),
                .product(name: "Qwen3ASR", package: "speech-swift")
            ]
        )
    ]
)
