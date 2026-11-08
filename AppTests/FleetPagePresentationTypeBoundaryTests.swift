import SwiftUI
import Testing
#if os(macOS)
@testable import HashFleetMac
#else
@testable import HashFleet
#endif

/// Guards the generic-type boundary in `fleetAppNavigation`.
///
/// The November 7, 2026 physical iPhone report was a scene-create watchdog kill whose main-thread
/// sample contained 160 of 328 frames in the Swift demangler (`swift_getTypeName` from
/// `AGGraphInternAttributeType` under `ConditionalMetadata.makeViewList`). That is a frame count,
/// not a time attribution. Un-erased `decorate(self)` roughly doubles the runtime type name per
/// chained presentation modifier.
///
/// These tests measure the production modifier's runtime type-name size, the kind of size implicated
/// by the sampled demangling stack, not the exact type of the crashed build. They do not measure
/// iPhone scene-create time and are not physical-device acceptance.
@Suite("Fleet page presentation type boundary")
@MainActor
struct FleetPagePresentationTypeBoundaryTests {
    private struct Leaf: View {
        var body: some View { Text("leaf") }
    }

    private struct Route: Identifiable, Hashable { let id: Int }

    /// Regression budget for these representative presentation chains. The real dashboard
    /// destinations are not measured here. Measured optimized macOS values for the erased boundary
    /// are 114 to 679 bytes. The pre-d1f39b2 shape reached 1.65 MB at depth 11.
    private static let typeNameByteBudget = 8_192

    private static func typeNameBytes<V: View>(_ view: V) -> Int {
        _typeName(type(of: view), qualified: true).utf8.count
    }

    private var isPresented: Binding<Bool> { .constant(false) }
    private var item: Binding<Route?> { .constant(nil) }

    @Test("Eleven chained Bool presentations keep a constant type-name size")
    func boolChainIsDepthIndependent() {
        let base = Leaf().fleetAppNavigation { $0.navigationTitle("Title") }
        let one = base.fleetPagePresentation(isPresented: isPresented) { Text("1") }
        var sizes = [Self.typeNameBytes(one)]
        let two = one.fleetPagePresentation(isPresented: isPresented) { Text("2") }
        sizes.append(Self.typeNameBytes(two))
        let three = two.fleetPagePresentation(isPresented: isPresented) { Text("3") }
        sizes.append(Self.typeNameBytes(three))
        let four = three.fleetPagePresentation(isPresented: isPresented) { Text("4") }
        sizes.append(Self.typeNameBytes(four))
        let five = four.fleetPagePresentation(isPresented: isPresented) { Text("5") }
        sizes.append(Self.typeNameBytes(five))
        let six = five.fleetPagePresentation(isPresented: isPresented) { Text("6") }
        sizes.append(Self.typeNameBytes(six))
        let seven = six.fleetPagePresentation(isPresented: isPresented) { Text("7") }
        sizes.append(Self.typeNameBytes(seven))
        let eight = seven.fleetPagePresentation(isPresented: isPresented) { Text("8") }
        sizes.append(Self.typeNameBytes(eight))
        let nine = eight.fleetPagePresentation(isPresented: isPresented) { Text("9") }
        sizes.append(Self.typeNameBytes(nine))
        let ten = nine.fleetPagePresentation(isPresented: isPresented) { Text("10") }
        sizes.append(Self.typeNameBytes(ten))
        let eleven = ten.fleetPagePresentation(isPresented: isPresented) { Text("11") }
        sizes.append(Self.typeNameBytes(eleven))
        let thirteen = eleven
            .fleetPagePresentation(isPresented: isPresented) { Text("12") }
            .fleetPagePresentation(isPresented: isPresented) { Text("13") }
        sizes.append(Self.typeNameBytes(thirteen))

        #expect(Set(sizes).count == 1, "Type-name size must not depend on chain depth: \(sizes)")
        #expect(sizes.allSatisfy { $0 < Self.typeNameByteBudget }, "\(sizes)")
    }

    @Test("Mixed Bool, item and destination decorators stay inside the byte budget")
    func mixedDashboardShapeStaysBounded() {
        let view = Leaf()
            .fleetAppNavigation { $0.navigationTitle("Title") }
            .fleetPagePresentation(isPresented: isPresented) { Text("a") }
            .fleetPagePresentation(item: item) { route in Text("\(route.id)") }
            .fleetPagePresentation(isPresented: isPresented) { Text("b") }
            .fleetPagePresentation(isPresented: isPresented) { Text("c") }
            .fleetPagePresentation(item: item) { route in Text("\(route.id)") }
            .fleetPagePresentation(isPresented: isPresented) { Text("d") }
            .fleetPagePresentation(isPresented: isPresented) { Text("e") }
            .fleetPagePresentation(isPresented: isPresented) { Text("f") }
            .fleetPagePresentation(isPresented: isPresented) { Text("g") }
            .fleetPagePresentation(isPresented: isPresented) { Text("h") }
            .fleetPagePresentation(isPresented: isPresented) { Text("i") }
            .fleetAppNavigation { base in
                base.navigationDestination(item: item) { route in Text("\(route.id)") }
            }
            .fleetPagePresentation(isPresented: isPresented) { Text("j") }
        let bytes = Self.typeNameBytes(view)
        #expect(bytes < Self.typeNameByteBudget, "type name bytes \(bytes)")
    }

    // MARK: Negative control

    /// Faithful replica of the pre-d1f39b2 iOS shape: the decorator receives the whole growing
    /// `Self` and every presentation lowers it into both conditional branches.
    private static func legacyPresentation<V: View>(_ view: V) -> some View {
        legacyAppNavigation(view) { base in
            if ProcessInfo.processInfo.arguments.count > 1_000_000 {
                base.navigationDestination(isPresented: .constant(false)) { Text("destination") }
            } else {
                base.sheet(isPresented: .constant(false)) { Text("sheet") }
            }
        }
    }

    private static func legacyAppNavigation<V: View, D: View>(
        _ view: V, @ViewBuilder _ decorate: (V) -> D
    ) -> some View {
        decorate(view)
    }

    @Test("Negative control: the pre-fix un-erased shape grows geometrically, so the metric is sensitive")
    func unerasedShapeGrowsGeometrically() {
        let one = Self.legacyPresentation(Leaf())
        let two = Self.legacyPresentation(one)
        let three = Self.legacyPresentation(two)
        let four = Self.legacyPresentation(three)
        let five = Self.legacyPresentation(four)
        let legacyGrowth = Double(Self.typeNameBytes(five)) / Double(Self.typeNameBytes(two))
        #expect(legacyGrowth > 4, "legacy growth over 3 levels was \(legacyGrowth)")
        #expect(Self.typeNameBytes(five) > Self.typeNameByteBudget / 2)
    }
}
