import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import SQLite3

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(SwiftLiteMacros)
import SwiftLiteMacros

let testMacros: [String: Macro.Type] = [
    "stringify": StringifyMacro.self,
    "Model": ModelMacro.self,
    "Stored": StoredMacro.self,
]
#endif

final class SwiftLiteTests: XCTestCase
{
    func checkMacroAvailability() throws
    {
        #if !canImport(SwiftLiteMacros)
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testMacro() throws
    {
        try checkMacroAvailability()
        assertMacroExpansion(
            """
            #stringify(a + b)
            """,
            expandedSource: """
            (a + b, "a + b")
            """,
            macros: testMacros
        )
    }
    
    func testMacroWithStringLiteral() throws
    {
        try checkMacroAvailability()
        assertMacroExpansion(
            #"""
            #stringify("Hello, \(name)")
            """#,
            expandedSource: #"""
            ("Hello, \(name)", #""Hello, \(name)""#)
            """#,
            macros: testMacros
        )
    }
    
    func testModelMacro() throws
    {
        try checkMacroAvailability()

        // TODO: Update
        assertMacroExpansion(
            """
            class Test {
                @Model class Car {
                    var year: Int
                    var réböt: String
                    @InverseRelatedMany(\\Car.passengers)
                    var cars: CarCollection
                }
                @Model class 车 {}
                @Model class Մեքենա {}
            }
            """,
            expandedSource: """
            class Test {
                class Car {

                    static let table = "test__car"

                    static let fields = []
            }
                class 车 {

                    static let table = "test__u8f66"

                    static let fields = []
            }
                class Մեքենա {

                    static let table = "test__u574u565u584u565u576u561"

                    static let fields = []
            }
            }
            """,
            macros: testMacros
        )
    }
    
    func testStoredWithDefaultValueDiagnostic() throws
    {
        try checkMacroAvailability()
        
        assertMacroExpansion(
            """
            @Model final class Interior {
                @Stored
                let name: String = "gna"
            }
            """,
            expandedSource: """
            @Model final class Interior {
                @Stored
                let name: String
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Stored properties cannot have default values; use the 'defaultValue' parameter instead",
                    line: 3,
                    column: 22,
                    severity: .error,
                    fixIts: [
                        FixItSpec(message: "Move default value to '@Stored(defaultValue:)' parameter")
                    ]
                )
            ],
            macros: testMacros
        )
    }
}
