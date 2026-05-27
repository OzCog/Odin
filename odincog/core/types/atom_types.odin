// OdinCog - OpenCog Implementation in Pure Odin
// Core Type System - Atom Types
//
// This module defines the fundamental atom types for the OpenCog hypergraph.
// Atoms are the basic units of knowledge representation, consisting of Nodes
// (with names) and Links (connecting other atoms).

package odincog_types

// AtomType represents all possible atom types in OpenCog.
// These are organized hierarchically: Node types and Link types.
AtomType :: enum u16 {
    // Invalid/Unknown type
    INVALID = 0,
    
    // =========================================================================
    // BASE TYPES
    // =========================================================================
    ATOM,
    NODE,
    LINK,
    
    // =========================================================================
    // NODE TYPES
    // =========================================================================
    
    // Basic Nodes
    CONCEPT_NODE,           // Generic concept
    PREDICATE_NODE,         // Predicate (relation) name
    SCHEMA_NODE,            // Executable schema name
    GROUNDED_SCHEMA_NODE,   // Foreign function reference
    GROUNDED_PREDICATE_NODE,// Foreign predicate reference
    
    // Variable Nodes (for pattern matching)
    VARIABLE_NODE,          // Pattern variable
    GLOB_NODE,              // Glob variable (matches multiple atoms)
    TYPE_NODE,              // Type specification
    
    // Number and String Nodes
    NUMBER_NODE,            // Numeric value
    STRING_NODE,            // String value
    
    // Time Nodes
    TIME_NODE,              // Timestamp
    
    // Word/Language Nodes
    WORD_NODE,              // Natural language word
    LEMMA_NODE,             // Word lemma
    PHRASE_NODE,            // Multi-word phrase
    SENTENCE_NODE,          // Sentence identifier
    DOCUMENT_NODE,          // Document identifier
    
    // Definition Nodes
    DEFINED_SCHEMA_NODE,    // Named schema definition
    DEFINED_PREDICATE_NODE, // Named predicate definition
    DEFINED_TYPE_NODE,      // Named type definition
    
    // Anchor Nodes
    ANCHOR_NODE,            // Named reference point
    
    // =========================================================================
    // LINK TYPES - Ordered Links
    // =========================================================================
    
    // Basic Ordered Links
    ORDERED_LINK,           // Generic ordered link
    LIST_LINK,              // Simple list container
    
    // Logical Links (PLN)
    AND_LINK,               // Logical AND
    OR_LINK,                // Logical OR
    NOT_LINK,               // Logical NOT
    IMPLICATION_LINK,       // A implies B
    EQUIVALENCE_LINK,       // A equivalent to B
    
    // Quantifier Links
    FOR_ALL_LINK,           // Universal quantifier
    EXISTS_LINK,            // Existential quantifier
    
    // Evaluation Links
    EVALUATION_LINK,        // (Predicate, ListLink of args)
    EXECUTION_LINK,         // Schema execution
    EXECUTION_OUTPUT_LINK,  // Schema with output
    
    // Lambda and Scoping
    LAMBDA_LINK,            // Lambda abstraction
    SCOPE_LINK,             // Variable scope
    PUT_LINK,               // Substitution
    GET_LINK,               // Pattern query
    
    // Contextual Links
    CONTEXT_LINK,           // Context wrapper
    DEFINE_LINK,            // Definition
    
    // Sequential Links
    SEQUENTIAL_AND_LINK,    // Sequential AND
    SEQUENTIAL_OR_LINK,     // Sequential OR
    
    // State Links
    STATE_LINK,             // Mutable state
    
    // =========================================================================
    // LINK TYPES - Unordered Links
    // =========================================================================
    
    UNORDERED_LINK,         // Generic unordered link
    SET_LINK,               // Set of atoms
    
    // =========================================================================
    // INHERITANCE/SIMILARITY LINKS
    // =========================================================================
    
    INHERITANCE_LINK,       // A inherits from B (subset)
    SIMILARITY_LINK,        // A similar to B (symmetric)
    SUBSET_LINK,            // Extensional subset
    INTENSIONAL_INHERITANCE_LINK,
    INTENSIONAL_SIMILARITY_LINK,
    
    // =========================================================================
    // MEMBER LINKS
    // =========================================================================
    
    MEMBER_LINK,            // A is member of B
    
    // =========================================================================
    // ASSOCIATIVE LINKS
    // =========================================================================
    
    ASSOCIATIVE_LINK,       // Generic association
    HEBBIAN_LINK,           // Hebbian association (attention)
    ASYMMETRIC_HEBBIAN_LINK,
    SYMMETRIC_HEBBIAN_LINK,
    INVERSE_HEBBIAN_LINK,
    
    // =========================================================================
    // PATTERN MATCHING LINKS
    // =========================================================================
    
    BIND_LINK,              // Pattern + Rewrite rule
    SATISFACTION_LINK,      // Pattern satisfaction check
    QUERY_LINK,             // Pattern query
    
    // Variable Declaration Links
    VARIABLE_LIST,          // List of variables
    TYPED_VARIABLE_LINK,    // Variable with type constraint
    VARIABLE_SET,           // Unordered variable set
    
    // Type Specification Links
    TYPE_CHOICE,            // Type union
    TYPE_SET_LINK,          // Type intersection
    SIGNATURE_LINK,         // Type signature
    ARROW_LINK,             // Function type arrow
    
    // =========================================================================
    // ATTENTION LINKS
    // =========================================================================
    
    ATTENTION_LINK,         // Attention value carrier
    
    // =========================================================================
    // HIGHER-ORDER LINKS
    // =========================================================================
    
    QUOTE_LINK,             // Quote (prevent evaluation)
    UNQUOTE_LINK,           // Unquote (force evaluation)
    LOCAL_QUOTE_LINK,       // Local quote
    DONT_EXEC_LINK,         // Prevent execution
    
    // =========================================================================
    // VIRTUAL LINKS (for computation)
    // =========================================================================
    
    // Arithmetic
    PLUS_LINK,
    MINUS_LINK,
    TIMES_LINK,
    DIVIDE_LINK,
    
    // Comparison
    GREATER_THAN_LINK,
    LESS_THAN_LINK,
    EQUAL_LINK,
    NOT_EQUAL_LINK,
    
    // Boolean
    TRUE_LINK,
    FALSE_LINK,
    
    // =========================================================================
    // Reserved for extension
    // =========================================================================
    
    USER_DEFINED_START = 1000,
}

// Type hierarchy parent relationships
// Returns the parent type of a given atom type
get_parent_type :: proc(t: AtomType) -> AtomType {
    #partial switch t {
        // Nodes inherit from NODE
        case .CONCEPT_NODE, .PREDICATE_NODE, .SCHEMA_NODE, .GROUNDED_SCHEMA_NODE,
             .GROUNDED_PREDICATE_NODE, .VARIABLE_NODE, .GLOB_NODE, .TYPE_NODE,
             .NUMBER_NODE, .STRING_NODE, .TIME_NODE, .WORD_NODE, .LEMMA_NODE,
             .PHRASE_NODE, .SENTENCE_NODE, .DOCUMENT_NODE, .DEFINED_SCHEMA_NODE,
             .DEFINED_PREDICATE_NODE, .DEFINED_TYPE_NODE, .ANCHOR_NODE:
            return .NODE
        
        // Ordered links
        case .LIST_LINK, .AND_LINK, .OR_LINK, .NOT_LINK, .IMPLICATION_LINK,
             .EQUIVALENCE_LINK, .FOR_ALL_LINK, .EXISTS_LINK, .EVALUATION_LINK,
             .EXECUTION_LINK, .EXECUTION_OUTPUT_LINK, .LAMBDA_LINK, .SCOPE_LINK,
             .PUT_LINK, .GET_LINK, .CONTEXT_LINK, .DEFINE_LINK,
             .SEQUENTIAL_AND_LINK, .SEQUENTIAL_OR_LINK, .STATE_LINK,
             .BIND_LINK, .SATISFACTION_LINK, .QUERY_LINK, .VARIABLE_LIST,
             .TYPED_VARIABLE_LINK, .TYPE_CHOICE, .SIGNATURE_LINK, .ARROW_LINK,
             .QUOTE_LINK, .UNQUOTE_LINK, .LOCAL_QUOTE_LINK, .DONT_EXEC_LINK,
             .PLUS_LINK, .MINUS_LINK, .TIMES_LINK, .DIVIDE_LINK,
             .GREATER_THAN_LINK, .LESS_THAN_LINK, .EQUAL_LINK, .NOT_EQUAL_LINK:
            return .ORDERED_LINK
        
        // Unordered links
        case .SET_LINK, .SIMILARITY_LINK, .INTENSIONAL_SIMILARITY_LINK,
             .VARIABLE_SET, .TYPE_SET_LINK, .SYMMETRIC_HEBBIAN_LINK:
            return .UNORDERED_LINK
        
        // Inheritance-style links
        case .INHERITANCE_LINK, .SUBSET_LINK, .INTENSIONAL_INHERITANCE_LINK,
             .MEMBER_LINK:
            return .ORDERED_LINK
        
        // Associative links
        case .HEBBIAN_LINK, .ASYMMETRIC_HEBBIAN_LINK, .INVERSE_HEBBIAN_LINK:
            return .ASSOCIATIVE_LINK
        
        // Base link types
        case .ORDERED_LINK, .UNORDERED_LINK, .ASSOCIATIVE_LINK:
            return .LINK
        
        // Top-level types
        case .NODE, .LINK:
            return .ATOM
        
        case .ATOM:
            return .INVALID
        
        case:
            return .INVALID
    }
}

// Type predicates

is_node :: proc(t: AtomType) -> bool {
    parent := t
    for parent != .INVALID {
        if parent == .NODE {
            return true
        }
        parent = get_parent_type(parent)
    }
    return false
}

is_link :: proc(t: AtomType) -> bool {
    parent := t
    for parent != .INVALID {
        if parent == .LINK {
            return true
        }
        parent = get_parent_type(parent)
    }
    return false
}

is_ordered_link :: proc(t: AtomType) -> bool {
    parent := t
    for parent != .INVALID {
        if parent == .ORDERED_LINK {
            return true
        }
        parent = get_parent_type(parent)
    }
    return false
}

is_unordered_link :: proc(t: AtomType) -> bool {
    parent := t
    for parent != .INVALID {
        if parent == .UNORDERED_LINK {
            return true
        }
        parent = get_parent_type(parent)
    }
    return false
}

is_variable :: proc(t: AtomType) -> bool {
    return t == .VARIABLE_NODE || t == .GLOB_NODE
}

is_logical_link :: proc(t: AtomType) -> bool {
    #partial switch t {
        case .AND_LINK, .OR_LINK, .NOT_LINK, .IMPLICATION_LINK, .EQUIVALENCE_LINK:
            return true
        case:
            return false
    }
}

is_quantifier :: proc(t: AtomType) -> bool {
    return t == .FOR_ALL_LINK || t == .EXISTS_LINK
}

is_scope_link :: proc(t: AtomType) -> bool {
    #partial switch t {
        case .SCOPE_LINK, .LAMBDA_LINK, .BIND_LINK, .GET_LINK, .SATISFACTION_LINK,
             .FOR_ALL_LINK, .EXISTS_LINK:
            return true
        case:
            return false
    }
}

is_evaluatable :: proc(t: AtomType) -> bool {
    #partial switch t {
        case .EVALUATION_LINK, .EXECUTION_LINK, .EXECUTION_OUTPUT_LINK,
             .PLUS_LINK, .MINUS_LINK, .TIMES_LINK, .DIVIDE_LINK,
             .GREATER_THAN_LINK, .LESS_THAN_LINK, .EQUAL_LINK, .NOT_EQUAL_LINK,
             .AND_LINK, .OR_LINK, .NOT_LINK:
            return true
        case:
            return false
    }
}

// Check if type a is a subtype of type b
is_subtype_of :: proc(a: AtomType, b: AtomType) -> bool {
    if a == b {
        return true
    }
    
    current := a
    for current != .INVALID {
        if current == b {
            return true
        }
        current = get_parent_type(current)
    }
    return false
}

// Get human-readable type name
type_name :: proc(t: AtomType) -> string {
    #partial switch t {
        case .INVALID: return "Invalid"
        case .ATOM: return "Atom"
        case .NODE: return "Node"
        case .LINK: return "Link"
        case .CONCEPT_NODE: return "ConceptNode"
        case .PREDICATE_NODE: return "PredicateNode"
        case .SCHEMA_NODE: return "SchemaNode"
        case .GROUNDED_SCHEMA_NODE: return "GroundedSchemaNode"
        case .GROUNDED_PREDICATE_NODE: return "GroundedPredicateNode"
        case .VARIABLE_NODE: return "VariableNode"
        case .GLOB_NODE: return "GlobNode"
        case .TYPE_NODE: return "TypeNode"
        case .NUMBER_NODE: return "NumberNode"
        case .STRING_NODE: return "StringNode"
        case .TIME_NODE: return "TimeNode"
        case .WORD_NODE: return "WordNode"
        case .LEMMA_NODE: return "LemmaNode"
        case .PHRASE_NODE: return "PhraseNode"
        case .SENTENCE_NODE: return "SentenceNode"
        case .DOCUMENT_NODE: return "DocumentNode"
        case .DEFINED_SCHEMA_NODE: return "DefinedSchemaNode"
        case .DEFINED_PREDICATE_NODE: return "DefinedPredicateNode"
        case .DEFINED_TYPE_NODE: return "DefinedTypeNode"
        case .ANCHOR_NODE: return "AnchorNode"
        case .ORDERED_LINK: return "OrderedLink"
        case .LIST_LINK: return "ListLink"
        case .AND_LINK: return "AndLink"
        case .OR_LINK: return "OrLink"
        case .NOT_LINK: return "NotLink"
        case .IMPLICATION_LINK: return "ImplicationLink"
        case .EQUIVALENCE_LINK: return "EquivalenceLink"
        case .FOR_ALL_LINK: return "ForAllLink"
        case .EXISTS_LINK: return "ExistsLink"
        case .EVALUATION_LINK: return "EvaluationLink"
        case .EXECUTION_LINK: return "ExecutionLink"
        case .EXECUTION_OUTPUT_LINK: return "ExecutionOutputLink"
        case .LAMBDA_LINK: return "LambdaLink"
        case .SCOPE_LINK: return "ScopeLink"
        case .PUT_LINK: return "PutLink"
        case .GET_LINK: return "GetLink"
        case .CONTEXT_LINK: return "ContextLink"
        case .DEFINE_LINK: return "DefineLink"
        case .SEQUENTIAL_AND_LINK: return "SequentialAndLink"
        case .SEQUENTIAL_OR_LINK: return "SequentialOrLink"
        case .STATE_LINK: return "StateLink"
        case .UNORDERED_LINK: return "UnorderedLink"
        case .SET_LINK: return "SetLink"
        case .INHERITANCE_LINK: return "InheritanceLink"
        case .SIMILARITY_LINK: return "SimilarityLink"
        case .SUBSET_LINK: return "SubsetLink"
        case .INTENSIONAL_INHERITANCE_LINK: return "IntensionalInheritanceLink"
        case .INTENSIONAL_SIMILARITY_LINK: return "IntensionalSimilarityLink"
        case .MEMBER_LINK: return "MemberLink"
        case .ASSOCIATIVE_LINK: return "AssociativeLink"
        case .HEBBIAN_LINK: return "HebbianLink"
        case .ASYMMETRIC_HEBBIAN_LINK: return "AsymmetricHebbianLink"
        case .SYMMETRIC_HEBBIAN_LINK: return "SymmetricHebbianLink"
        case .INVERSE_HEBBIAN_LINK: return "InverseHebbianLink"
        case .BIND_LINK: return "BindLink"
        case .SATISFACTION_LINK: return "SatisfactionLink"
        case .QUERY_LINK: return "QueryLink"
        case .VARIABLE_LIST: return "VariableList"
        case .TYPED_VARIABLE_LINK: return "TypedVariableLink"
        case .VARIABLE_SET: return "VariableSet"
        case .TYPE_CHOICE: return "TypeChoice"
        case .TYPE_SET_LINK: return "TypeSetLink"
        case .SIGNATURE_LINK: return "SignatureLink"
        case .ARROW_LINK: return "ArrowLink"
        case .ATTENTION_LINK: return "AttentionLink"
        case .QUOTE_LINK: return "QuoteLink"
        case .UNQUOTE_LINK: return "UnquoteLink"
        case .LOCAL_QUOTE_LINK: return "LocalQuoteLink"
        case .DONT_EXEC_LINK: return "DontExecLink"
        case .PLUS_LINK: return "PlusLink"
        case .MINUS_LINK: return "MinusLink"
        case .TIMES_LINK: return "TimesLink"
        case .DIVIDE_LINK: return "DivideLink"
        case .GREATER_THAN_LINK: return "GreaterThanLink"
        case .LESS_THAN_LINK: return "LessThanLink"
        case .EQUAL_LINK: return "EqualLink"
        case .NOT_EQUAL_LINK: return "NotEqualLink"
        case .TRUE_LINK: return "TrueLink"
        case .FALSE_LINK: return "FalseLink"
        case: return "Unknown"
    }
}
