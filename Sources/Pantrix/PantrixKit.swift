
// The umbrella module consumers `import Pantrix` — the iOS analogue of Android's fused AAR.
// It fuses the shipped pieces so a single import exposes everything:
//   • `PantrixCore` — the closed `PantrixCore.xcframework` (facade, pipeline, collectors)
//
// compiled from source; only `PantrixCore` is the binary.
@_exported import PantrixCore
