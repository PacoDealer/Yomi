// swift-tools-version: 6.1
// Vendored PLzmaSDK 1.6.1 (commit f449bc3), see VENDORED.md. Upstream's manifest minus the test targets, plus
// -Wno-deprecated-declarations on the C/C++ target (readdir_r in plzma_path*.cpp; a local package shows its warnings).

import PackageDescription

let package = Package(
    name: "PLzmaSDK",
    products: [
        .library(name: "PLzmaSDK", targets: ["PLzmaSDK"])
    ],
    targets: [
        .target(name: "libplzma",
                path: "src",
                cSettings: [
                    .define("LIBPLZMA_VERSION_BUILD", to: "1466"),
                    .unsafeFlags(["-fPIC", "-Wno-deprecated-declarations"])
                ],
                cxxSettings: [
                    .define("LIBPLZMA_VERSION_BUILD", to: "1466"),
                    .unsafeFlags(["-fPIC", "-fno-rtti", "-Wno-deprecated-declarations"])
                ]),
        .target(name: "PLzmaSDK",
                dependencies: [
                    .target(name: "libplzma")
                ],
                path: "swift",
                resources: [
                    .copy("../resources/PrivacyInfo.xcprivacy"),
                ])
    ],
    swiftLanguageModes: [.v5, .v6],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx11
)
