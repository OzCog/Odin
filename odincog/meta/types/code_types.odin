// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Code Atom Types
//
// This module extends the OpenCog atom type system with types for
// representing code structure. These enable the agent to reason about
// its own codebase as part of its world model.

package odincog_code_types

import "../../core/types"

// =============================================================================
// CODE-RELATED ATOM TYPES
// =============================================================================

// CodeAtomType extends the base atom types with code-specific types
CodeAtomType :: enum u16 {
    // =========================================================================
    // CODE NODE TYPES
    // =========================================================================
    
    // Procedure representation
    PROCEDURE_NODE = 1100,      // An executable procedure/function
    METHOD_NODE,                // A method (procedure bound to type)
    CLOSURE_NODE,               // A closure/lambda
    
    // Module/Package representation
    MODULE_NODE,                // A module or package
    PACKAGE_NODE,               // A package (collection of modules)
    
    // Type representation
    CODE_TYPE_NODE,             // A data type definition
    STRUCT_NODE,                // A struct type
    ENUM_NODE,                  // An enum type
    UNION_NODE,                 // A union type
    INTERFACE_NODE,             // An interface/trait
    
    // Variable representation
    LOCAL_VAR_NODE,             // A local variable
    GLOBAL_VAR_NODE,            // A global variable
    PARAMETER_NODE,             // A function parameter
    CONSTANT_NODE,              // A constant value
    
    // File representation
    SOURCE_FILE_NODE,           // A source code file
    
    // =========================================================================
    // CODE LINK TYPES
    // =========================================================================
    
    // Structural links
    DEFINES_LINK = 1200,        // Module/file defines procedure/type
    IMPORTS_LINK,               // Module imports another module
    EXPORTS_LINK,               // Module exports symbols
    CONTAINS_LINK,              // Scope contains symbol
    
    // Call graph links
    CALLS_LINK,                 // Procedure calls procedure
    RETURNS_LINK,               // Procedure returns type
    TAKES_LINK,                 // Procedure takes parameter type
    
    // Data flow links
    READS_LINK,                 // Procedure reads variable
    WRITES_LINK,                // Procedure writes variable
    MUTATES_LINK,               // Procedure mutates atom type
    
    // Type relationship links
    EXTENDS_LINK,               // Type extends another type
    IMPLEMENTS_LINK,            // Type implements interface
    HAS_FIELD_LINK,             // Struct has field of type
    
    // Transformation links
    TRANSFORM_LINK,             // Links pattern to transformation
    REWRITE_LINK,               // Rewrite rule
    MACRO_EXPAND_LINK,          // Macro expansion
    
    // Meta links
    META_PATTERN_LINK,          // Meta-pattern (pattern over code)
    ANNOTATION_LINK,            // Code annotation/attribute
    DEPENDENCY_LINK,            // Dependency relationship
}

// =============================================================================
// TYPE PREDICATES
// =============================================================================

// Check if type is a code node type
is_code_node :: proc(t: CodeAtomType) -> bool {
    return t >= .PROCEDURE_NODE && t < .DEFINES_LINK
}

// Check if type is a code link type
is_code_link :: proc(t: CodeAtomType) -> bool {
    return t >= .DEFINES_LINK
}

// Check if type represents a callable entity
is_callable :: proc(t: CodeAtomType) -> bool {
    #partial switch t {
        case .PROCEDURE_NODE, .METHOD_NODE, .CLOSURE_NODE:
            return true
        case:
            return false
    }
}

// Check if type represents a type definition
is_type_def :: proc(t: CodeAtomType) -> bool {
    #partial switch t {
        case .CODE_TYPE_NODE, .STRUCT_NODE, .ENUM_NODE, .UNION_NODE, .INTERFACE_NODE:
            return true
        case:
            return false
    }
}

// Check if type represents a variable
is_variable_def :: proc(t: CodeAtomType) -> bool {
    #partial switch t {
        case .LOCAL_VAR_NODE, .GLOBAL_VAR_NODE, .PARAMETER_NODE, .CONSTANT_NODE:
            return true
        case:
            return false
    }
}

// Check if type represents a structural relationship
is_structural_link :: proc(t: CodeAtomType) -> bool {
    #partial switch t {
        case .DEFINES_LINK, .IMPORTS_LINK, .EXPORTS_LINK, .CONTAINS_LINK:
            return true
        case:
            return false
    }
}

// Check if type represents a call relationship
is_call_link :: proc(t: CodeAtomType) -> bool {
    #partial switch t {
        case .CALLS_LINK, .RETURNS_LINK, .TAKES_LINK:
            return true
        case:
            return false
    }
}

// Check if type represents a data flow relationship
is_dataflow_link :: proc(t: CodeAtomType) -> bool {
    #partial switch t {
        case .READS_LINK, .WRITES_LINK, .MUTATES_LINK:
            return true
        case:
            return false
    }
}

// =============================================================================
// TYPE NAME MAPPING
// =============================================================================

// Get human-readable name for code atom type
code_type_name :: proc(t: CodeAtomType) -> string {
    #partial switch t {
        case .PROCEDURE_NODE: return "ProcedureNode"
        case .METHOD_NODE: return "MethodNode"
        case .CLOSURE_NODE: return "ClosureNode"
        case .MODULE_NODE: return "ModuleNode"
        case .PACKAGE_NODE: return "PackageNode"
        case .CODE_TYPE_NODE: return "CodeTypeNode"
        case .STRUCT_NODE: return "StructNode"
        case .ENUM_NODE: return "EnumNode"
        case .UNION_NODE: return "UnionNode"
        case .INTERFACE_NODE: return "InterfaceNode"
        case .LOCAL_VAR_NODE: return "LocalVarNode"
        case .GLOBAL_VAR_NODE: return "GlobalVarNode"
        case .PARAMETER_NODE: return "ParameterNode"
        case .CONSTANT_NODE: return "ConstantNode"
        case .SOURCE_FILE_NODE: return "SourceFileNode"
        case .DEFINES_LINK: return "DefinesLink"
        case .IMPORTS_LINK: return "ImportsLink"
        case .EXPORTS_LINK: return "ExportsLink"
        case .CONTAINS_LINK: return "ContainsLink"
        case .CALLS_LINK: return "CallsLink"
        case .RETURNS_LINK: return "ReturnsLink"
        case .TAKES_LINK: return "TakesLink"
        case .READS_LINK: return "ReadsLink"
        case .WRITES_LINK: return "WritesLink"
        case .MUTATES_LINK: return "MutatesLink"
        case .EXTENDS_LINK: return "ExtendsLink"
        case .IMPLEMENTS_LINK: return "ImplementsLink"
        case .HAS_FIELD_LINK: return "HasFieldLink"
        case .TRANSFORM_LINK: return "TransformLink"
        case .REWRITE_LINK: return "RewriteLink"
        case .MACRO_EXPAND_LINK: return "MacroExpandLink"
        case .META_PATTERN_LINK: return "MetaPatternLink"
        case .ANNOTATION_LINK: return "AnnotationLink"
        case .DEPENDENCY_LINK: return "DependencyLink"
        case: return "Unknown"
    }
}

// =============================================================================
// CODE ATOM PROPERTIES
// =============================================================================

// ProcedureInfo holds metadata about a procedure
ProcedureInfo :: struct {
    // Source location
    file:               string,
    line:               int,
    column:             int,
    
    // Signature
    param_types:        []string,
    return_type:        string,
    
    // Properties
    is_public:          bool,
    is_inline:          bool,
    is_pure:            bool,      // No side effects
    is_recursive:       bool,
    
    // Complexity metrics
    cyclomatic:         int,
    lines_of_code:      int,
    
    // Documentation
    doc_string:         string,
}

// ModuleInfo holds metadata about a module
ModuleInfo :: struct {
    // Path
    path:               string,
    package_name:       string,
    
    // Contents
    procedures:         []string,
    types:              []string,
    imports:            []string,
    
    // Properties
    is_public:          bool,
    
    // Metrics
    lines_of_code:      int,
    num_procedures:     int,
    num_types:          int,
}

// TypeInfo holds metadata about a type
TypeInfo :: struct {
    // Identity
    name:               string,
    kind:               CodeAtomType,
    
    // Structure
    fields:             []FieldInfo,
    methods:            []string,
    
    // Relationships
    extends:            string,
    implements:         []string,
    
    // Size
    size_bytes:         int,
    alignment:          int,
}

// FieldInfo holds metadata about a struct field
FieldInfo :: struct {
    name:               string,
    type_name:          string,
    offset:             int,
    is_public:          bool,
}

// =============================================================================
// CONVERSION UTILITIES
// =============================================================================

// Convert CodeAtomType to base AtomType offset
// This allows integrating code atoms with the main atom system
code_type_to_user_defined :: proc(t: CodeAtomType) -> types.AtomType {
    base := types.AtomType.USER_DEFINED_START
    return types.AtomType(int(base) + int(t))
}

// Convert from user-defined AtomType to CodeAtomType
user_defined_to_code_type :: proc(t: types.AtomType) -> (CodeAtomType, bool) {
    base := int(types.AtomType.USER_DEFINED_START)
    offset := int(t) - base
    
    if offset >= int(CodeAtomType.PROCEDURE_NODE) && offset <= int(CodeAtomType.DEPENDENCY_LINK) {
        return CodeAtomType(offset), true
    }
    return CodeAtomType(0), false
}

// =============================================================================
// SEMANTIC ROLES
// =============================================================================

// SemanticRole indicates the role an atom plays in code structure
SemanticRole :: enum {
    // Definitions
    DEFINER,            // Entity that defines something
    DEFINED,            // Entity being defined
    
    // Usage
    CALLER,             // Entity making a call
    CALLEE,             // Entity being called
    
    // Data flow
    SOURCE,             // Data source
    SINK,               // Data destination
    
    // Structure
    CONTAINER,          // Containing scope
    CONTAINED,          // Contained element
    
    // Types
    TYPE_PROVIDER,      // Entity providing type
    TYPE_CONSUMER,      // Entity consuming type
}

// Get the semantic role for a position in a link
get_semantic_role :: proc(t: CodeAtomType, position: int) -> SemanticRole {
    #partial switch t {
        case .DEFINES_LINK:
            return position == 0 ? .DEFINER : .DEFINED
        case .CALLS_LINK:
            return position == 0 ? .CALLER : .CALLEE
        case .READS_LINK, .WRITES_LINK:
            return position == 0 ? .CALLER : (position == 1 ? .SOURCE : .SINK)
        case .CONTAINS_LINK:
            return position == 0 ? .CONTAINER : .CONTAINED
        case .RETURNS_LINK, .TAKES_LINK:
            return position == 0 ? .TYPE_CONSUMER : .TYPE_PROVIDER
        case:
            return .DEFINED
    }
}
