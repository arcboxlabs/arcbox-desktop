import XCTest

@testable import ArcBox

final class ImageLayerChainTests: XCTestCase {
    func testSingleLayerChainIDIsTheDiffID() {
        // A single-layer image's top chain ID equals its only diff ID —
        // pinned against a live containerd committed-snapshot key
        // (alpine:latest, verified in the arcbox container_fs e2e).
        let diff = "sha256:b2848c02ac6ff53d265469b5b30f649f335e546a83330cd8916d54e65e640409"
        XCTAssertEqual(ImageLayerChain.topChainID(diffIDs: [diff]), diff)
    }

    func testMultiLayerChainIDFollowsTheOCIFormula() {
        // sha256("<chain0> <diff1>") computed independently with
        // `printf '%s %s' a b | shasum -a 256` over the literal IDs below.
        let diff0 = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
        let diff1 = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
        XCTAssertEqual(
            ImageLayerChain.topChainID(diffIDs: [diff0, diff1]),
            "sha256:f94b891e05f6e37c90d87edfd5bb98a02d618a437c35f3a94b3b00e48e894631"
        )
    }

    func testEmptyLayersYieldNil() {
        XCTAssertNil(ImageLayerChain.topChainID(diffIDs: []))
    }
}
