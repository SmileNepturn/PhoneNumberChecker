// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OcrVisionProbe",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ocr-vision-probe", targets: ["OcrVisionProbe"])
    ],
    targets: [
        .executableTarget(name: "OcrVisionProbe")
    ]
)
