// OdinCog - OpenCog Implementation in Pure Odin
// File Persistence - Atomese Serialization
//
// This module implements file-based persistence for the AtomSpace, supporting:
// - Atomese S-expression format (compatible with OpenCog)
// - JSON format for interoperability
// - Binary format for performance

package odincog_persist

import "core:os"
import "core:io"
import "core:bufio"
import "core:mem"
import "core:strings"
import "core:strconv"
import "core:fmt"
import "../../core/atom"
import "../../core/atomspace"
import "../../core/types"

// =============================================================================
// ATOMESE S-EXPRESSION FORMAT
// =============================================================================

// Save AtomSpace to file in Atomese format
save_atomese :: proc(as: ^atomspace.AtomSpace, filepath: string) -> bool {
    handle, err := os.open(filepath, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
    if err != nil {
        return false
    }
    defer os.close(handle)
    
    writer := io.to_writer(os.stream_from_handle(handle))
    
    // Write header comment
    io.write_string(writer, "; OdinCog AtomSpace dump\n")
    io.write_string(writer, "; Format: Atomese S-expression\n\n")
    
    // First pass: write all nodes
    io.write_string(writer, "; --- Nodes ---\n")
    it := atomspace.atomspace_iterator(as)
    for {
        a, _, ok := atomspace.atomspace_iterate(&it)
        if !ok {
            break
        }
        if atom.atom_is_node(a) {
            write_atom_atomese(writer, a, as)
            io.write_string(writer, "\n")
        }
    }
    
    // Second pass: write all links
    io.write_string(writer, "\n; --- Links ---\n")
    it = atomspace.atomspace_iterator(as)
    for {
        a, _, ok := atomspace.atomspace_iterate(&it)
        if !ok {
            break
        }
        if atom.atom_is_link(a) {
            write_atom_atomese(writer, a, as)
            io.write_string(writer, "\n")
        }
    }
    
    return true
}

// Write a single atom in Atomese format
write_atom_atomese :: proc(writer: io.Writer, a: ^atom.Atom, as: ^atomspace.AtomSpace) {
    io.write_string(writer, "(")
    io.write_string(writer, types.type_name(a.atom_type))
    
    if atom.atom_is_node(a) {
        io.write_string(writer, " \"")
        write_escaped_string(writer, atom.atom_get_name(a))
        io.write_string(writer, "\"")
    } else if atom.atom_is_link(a) {
        outgoing := atom.atom_get_outgoing(a)
        for h in outgoing {
            io.write_string(writer, "\n  ")
            if target, ok := atomspace.atomspace_get(as, h); ok {
                write_atom_atomese(writer, target, as)
            }
        }
    }
    
    // Write truth value if non-default
    if !atom.tv_is_default(a.truth_value) {
        io.write_string(writer, fmt.tprintf("\n  (stv %.6f %.6f)",
            atom.tv_get_strength(a.truth_value),
            atom.tv_get_confidence(a.truth_value)))
    }
    
    io.write_string(writer, ")")
}

// Write string with escaping
write_escaped_string :: proc(writer: io.Writer, s: string) {
    for c in s {
        switch c {
            case '\\': io.write_string(writer, "\\\\")
            case '"':  io.write_string(writer, "\\\"")
            case '\n': io.write_string(writer, "\\n")
            case '\r': io.write_string(writer, "\\r")
            case '\t': io.write_string(writer, "\\t")
            case:      io.write_byte(writer, u8(c))
        }
    }
}

// =============================================================================
// ATOMESE PARSER
// =============================================================================

// Token types for parsing
TokenType :: enum {
    LPAREN,
    RPAREN,
    STRING,
    SYMBOL,
    NUMBER,
    EOF,
    ERROR,
}

Token :: struct {
    type:  TokenType,
    value: string,
    line:  int,
    col:   int,
}

// Parser state
Parser :: struct {
    input:      string,
    pos:        int,
    line:       int,
    col:        int,
    atomspace:  ^atomspace.AtomSpace,
    allocator:  mem.Allocator,
}

// Load AtomSpace from Atomese file
load_atomese :: proc(as: ^atomspace.AtomSpace, filepath: string, allocator := context.allocator) -> bool {
    data, ok := os.read_entire_file(filepath, allocator)
    if !ok {
        return false
    }
    defer delete(data, allocator)
    
    return parse_atomese(as, string(data), allocator)
}

// Parse Atomese string into AtomSpace
parse_atomese :: proc(as: ^atomspace.AtomSpace, input: string, allocator := context.allocator) -> bool {
    parser := Parser{
        input = input,
        pos = 0,
        line = 1,
        col = 1,
        atomspace = as,
        allocator = allocator,
    }
    
    for {
        token := next_token(&parser)
        
        if token.type == .EOF {
            break
        }
        
        if token.type == .ERROR {
            return false
        }
        
        if token.type == .LPAREN {
            _, ok := parse_atom(&parser)
            if !ok {
                return false
            }
        }
    }
    
    return true
}

// Get next token
next_token :: proc(p: ^Parser) -> Token {
    skip_whitespace_and_comments(p)
    
    if p.pos >= len(p.input) {
        return Token{type = .EOF}
    }
    
    c := p.input[p.pos]
    
    switch c {
        case '(':
            p.pos += 1
            p.col += 1
            return Token{type = .LPAREN, line = p.line, col = p.col - 1}
        
        case ')':
            p.pos += 1
            p.col += 1
            return Token{type = .RPAREN, line = p.line, col = p.col - 1}
        
        case '"':
            return parse_string_token(p)
        
        case '0'..='9', '-', '.':
            return parse_number_token(p)
        
        case:
            return parse_symbol_token(p)
    }
}

// Skip whitespace and comments
skip_whitespace_and_comments :: proc(p: ^Parser) {
    for p.pos < len(p.input) {
        c := p.input[p.pos]
        
        if c == ' ' || c == '\t' || c == '\r' {
            p.pos += 1
            p.col += 1
        } else if c == '\n' {
            p.pos += 1
            p.line += 1
            p.col = 1
        } else if c == ';' {
            // Skip comment until end of line
            for p.pos < len(p.input) && p.input[p.pos] != '\n' {
                p.pos += 1
            }
        } else {
            break
        }
    }
}

// Parse string token
parse_string_token :: proc(p: ^Parser) -> Token {
    start_col := p.col
    p.pos += 1  // Skip opening quote
    p.col += 1
    
    builder := strings.builder_make(p.allocator)
    
    for p.pos < len(p.input) {
        c := p.input[p.pos]
        
        if c == '"' {
            p.pos += 1
            p.col += 1
            return Token{type = .STRING, value = strings.to_string(builder), line = p.line, col = start_col}
        } else if c == '\\' && p.pos + 1 < len(p.input) {
            p.pos += 1
            escape := p.input[p.pos]
            switch escape {
                case 'n':  strings.write_byte(&builder, '\n')
                case 'r':  strings.write_byte(&builder, '\r')
                case 't':  strings.write_byte(&builder, '\t')
                case '"':  strings.write_byte(&builder, '"')
                case '\\': strings.write_byte(&builder, '\\')
                case:      strings.write_byte(&builder, escape)
            }
            p.pos += 1
            p.col += 2
        } else {
            strings.write_byte(&builder, c)
            p.pos += 1
            p.col += 1
        }
    }
    
    return Token{type = .ERROR, value = "Unterminated string", line = p.line, col = start_col}
}

// Parse number token
parse_number_token :: proc(p: ^Parser) -> Token {
    start := p.pos
    start_col := p.col
    
    // Handle negative sign
    if p.input[p.pos] == '-' {
        p.pos += 1
        p.col += 1
    }
    
    // Parse digits and decimal point
    for p.pos < len(p.input) {
        c := p.input[p.pos]
        if (c >= '0' && c <= '9') || c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-' {
            p.pos += 1
            p.col += 1
        } else {
            break
        }
    }
    
    return Token{type = .NUMBER, value = p.input[start:p.pos], line = p.line, col = start_col}
}

// Parse symbol token
parse_symbol_token :: proc(p: ^Parser) -> Token {
    start := p.pos
    start_col := p.col
    
    for p.pos < len(p.input) {
        c := p.input[p.pos]
        if c == '(' || c == ')' || c == '"' || c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ';' {
            break
        }
        p.pos += 1
        p.col += 1
    }
    
    return Token{type = .SYMBOL, value = p.input[start:p.pos], line = p.line, col = start_col}
}

// Parse an atom expression
parse_atom :: proc(p: ^Parser) -> (atom.Handle, bool) {
    // First token should be atom type
    type_token := next_token(p)
    if type_token.type != .SYMBOL {
        return atom.INVALID_HANDLE, false
    }
    
    atom_type := parse_atom_type(type_token.value)
    if atom_type == .INVALID {
        return atom.INVALID_HANDLE, false
    }
    
    // Check if node or link
    if types.is_node(atom_type) {
        return parse_node(p, atom_type)
    } else if types.is_link(atom_type) {
        return parse_link(p, atom_type)
    }
    
    return atom.INVALID_HANDLE, false
}

// Parse a node
parse_node :: proc(p: ^Parser, atom_type: types.AtomType) -> (atom.Handle, bool) {
    // Next should be name string
    name_token := next_token(p)
    if name_token.type != .STRING {
        return atom.INVALID_HANDLE, false
    }
    
    // Parse optional truth value
    tv := atom.DEFAULT_TV
    
    peek := next_token(p)
    if peek.type == .LPAREN {
        // Check if it's a truth value
        tv_type := next_token(p)
        if tv_type.type == .SYMBOL && tv_type.value == "stv" {
            strength_token := next_token(p)
            conf_token := next_token(p)
            close := next_token(p)
            
            if strength_token.type == .NUMBER && conf_token.type == .NUMBER && close.type == .RPAREN {
                strength := strconv.parse_f64(strength_token.value) or_else 0.0
                conf := strconv.parse_f64(conf_token.value) or_else 0.0
                tv = atom.make_stv(strength, conf)
            }
        }
        
        // Consume closing paren of node
        peek = next_token(p)
    }
    
    if peek.type != .RPAREN {
        return atom.INVALID_HANDLE, false
    }
    
    // Add node to atomspace
    handle, _ := atomspace.add_node(p.atomspace, atom_type, name_token.value, tv)
    return handle, true
}

// Parse a link
parse_link :: proc(p: ^Parser, atom_type: types.AtomType) -> (atom.Handle, bool) {
    outgoing := make([dynamic]atom.Handle, p.allocator)
    defer delete(outgoing)
    
    tv := atom.DEFAULT_TV
    
    for {
        token := next_token(p)
        
        if token.type == .RPAREN {
            break
        }
        
        if token.type == .LPAREN {
            // Check if it's a truth value or nested atom
            peek := next_token(p)
            
            if peek.type == .SYMBOL && peek.value == "stv" {
                // Parse truth value
                strength_token := next_token(p)
                conf_token := next_token(p)
                close := next_token(p)
                
                if strength_token.type == .NUMBER && conf_token.type == .NUMBER && close.type == .RPAREN {
                    strength := strconv.parse_f64(strength_token.value) or_else 0.0
                    conf := strconv.parse_f64(conf_token.value) or_else 0.0
                    tv = atom.make_stv(strength, conf)
                }
            } else {
                // Parse nested atom - put the peek token back by adjusting position
                // This is simplified; in production you'd use a proper lookahead
                inner_type := parse_atom_type(peek.value)
                if inner_type != .INVALID {
                    if types.is_node(inner_type) {
                        h, ok := parse_node(p, inner_type)
                        if ok {
                            append(&outgoing, h)
                        }
                    } else if types.is_link(inner_type) {
                        h, ok := parse_link(p, inner_type)
                        if ok {
                            append(&outgoing, h)
                        }
                    }
                }
            }
        } else if token.type == .EOF || token.type == .ERROR {
            return atom.INVALID_HANDLE, false
        }
    }
    
    // Add link to atomspace
    handle, _ := atomspace.add_link(p.atomspace, atom_type, outgoing[:], tv)
    return handle, true
}

// Parse atom type from string
parse_atom_type :: proc(s: string) -> types.AtomType {
    switch s {
        case "ConceptNode":          return .CONCEPT_NODE
        case "PredicateNode":        return .PREDICATE_NODE
        case "SchemaNode":           return .SCHEMA_NODE
        case "GroundedSchemaNode":   return .GROUNDED_SCHEMA_NODE
        case "GroundedPredicateNode":return .GROUNDED_PREDICATE_NODE
        case "VariableNode":         return .VARIABLE_NODE
        case "GlobNode":             return .GLOB_NODE
        case "TypeNode":             return .TYPE_NODE
        case "NumberNode":           return .NUMBER_NODE
        case "StringNode":           return .STRING_NODE
        case "TimeNode":             return .TIME_NODE
        case "WordNode":             return .WORD_NODE
        case "LemmaNode":            return .LEMMA_NODE
        case "PhraseNode":           return .PHRASE_NODE
        case "SentenceNode":         return .SENTENCE_NODE
        case "DocumentNode":         return .DOCUMENT_NODE
        case "DefinedSchemaNode":    return .DEFINED_SCHEMA_NODE
        case "DefinedPredicateNode": return .DEFINED_PREDICATE_NODE
        case "DefinedTypeNode":      return .DEFINED_TYPE_NODE
        case "AnchorNode":           return .ANCHOR_NODE
        
        case "OrderedLink":          return .ORDERED_LINK
        case "ListLink":             return .LIST_LINK
        case "AndLink":              return .AND_LINK
        case "OrLink":               return .OR_LINK
        case "NotLink":              return .NOT_LINK
        case "ImplicationLink":      return .IMPLICATION_LINK
        case "EquivalenceLink":      return .EQUIVALENCE_LINK
        case "ForAllLink":           return .FOR_ALL_LINK
        case "ExistsLink":           return .EXISTS_LINK
        case "EvaluationLink":       return .EVALUATION_LINK
        case "ExecutionLink":        return .EXECUTION_LINK
        case "ExecutionOutputLink":  return .EXECUTION_OUTPUT_LINK
        case "LambdaLink":           return .LAMBDA_LINK
        case "ScopeLink":            return .SCOPE_LINK
        case "PutLink":              return .PUT_LINK
        case "GetLink":              return .GET_LINK
        case "ContextLink":          return .CONTEXT_LINK
        case "DefineLink":           return .DEFINE_LINK
        case "SequentialAndLink":    return .SEQUENTIAL_AND_LINK
        case "SequentialOrLink":     return .SEQUENTIAL_OR_LINK
        case "StateLink":            return .STATE_LINK
        case "UnorderedLink":        return .UNORDERED_LINK
        case "SetLink":              return .SET_LINK
        case "InheritanceLink":      return .INHERITANCE_LINK
        case "SimilarityLink":       return .SIMILARITY_LINK
        case "SubsetLink":           return .SUBSET_LINK
        case "IntensionalInheritanceLink": return .INTENSIONAL_INHERITANCE_LINK
        case "IntensionalSimilarityLink":  return .INTENSIONAL_SIMILARITY_LINK
        case "MemberLink":           return .MEMBER_LINK
        case "AssociativeLink":      return .ASSOCIATIVE_LINK
        case "HebbianLink":          return .HEBBIAN_LINK
        case "AsymmetricHebbianLink":return .ASYMMETRIC_HEBBIAN_LINK
        case "SymmetricHebbianLink": return .SYMMETRIC_HEBBIAN_LINK
        case "InverseHebbianLink":   return .INVERSE_HEBBIAN_LINK
        case "BindLink":             return .BIND_LINK
        case "SatisfactionLink":     return .SATISFACTION_LINK
        case "QueryLink":            return .QUERY_LINK
        case "VariableList":         return .VARIABLE_LIST
        case "TypedVariableLink":    return .TYPED_VARIABLE_LINK
        case "VariableSet":          return .VARIABLE_SET
        case "TypeChoice":           return .TYPE_CHOICE
        case "TypeSetLink":          return .TYPE_SET_LINK
        case "SignatureLink":        return .SIGNATURE_LINK
        case "ArrowLink":            return .ARROW_LINK
        case "AttentionLink":        return .ATTENTION_LINK
        case "QuoteLink":            return .QUOTE_LINK
        case "UnquoteLink":          return .UNQUOTE_LINK
        case "LocalQuoteLink":       return .LOCAL_QUOTE_LINK
        case "DontExecLink":         return .DONT_EXEC_LINK
        case "PlusLink":             return .PLUS_LINK
        case "MinusLink":            return .MINUS_LINK
        case "TimesLink":            return .TIMES_LINK
        case "DivideLink":           return .DIVIDE_LINK
        case "GreaterThanLink":      return .GREATER_THAN_LINK
        case "LessThanLink":         return .LESS_THAN_LINK
        case "EqualLink":            return .EQUAL_LINK
        case "NotEqualLink":         return .NOT_EQUAL_LINK
        case "TrueLink":             return .TRUE_LINK
        case "FalseLink":            return .FALSE_LINK
        
        case: return .INVALID
    }
}

// =============================================================================
// JSON FORMAT
// =============================================================================

// Save AtomSpace to JSON format
save_json :: proc(as: ^atomspace.AtomSpace, filepath: string) -> bool {
    handle, err := os.open(filepath, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
    if err != nil {
        return false
    }
    defer os.close(handle)
    
    writer := io.to_writer(os.stream_from_handle(handle))
    
    io.write_string(writer, "{\n  \"atoms\": [\n")
    
    first := true
    it := atomspace.atomspace_iterator(as)
    for {
        a, h, ok := atomspace.atomspace_iterate(&it)
        if !ok {
            break
        }
        
        if !first {
            io.write_string(writer, ",\n")
        }
        first = false
        
        write_atom_json(writer, a, h, as)
    }
    
    io.write_string(writer, "\n  ]\n}\n")
    return true
}

// Write atom in JSON format
write_atom_json :: proc(writer: io.Writer, a: ^atom.Atom, h: atom.Handle, as: ^atomspace.AtomSpace) {
    io.write_string(writer, "    {\n")
    io.write_string(writer, fmt.tprintf("      \"handle\": %d,\n", h.idx))
    io.write_string(writer, fmt.tprintf("      \"type\": \"%s\",\n", types.type_name(a.atom_type)))
    
    if atom.atom_is_node(a) {
        io.write_string(writer, fmt.tprintf("      \"name\": \"%s\",\n", escape_json_string(atom.atom_get_name(a))))
    } else if atom.atom_is_link(a) {
        io.write_string(writer, "      \"outgoing\": [")
        outgoing := atom.atom_get_outgoing(a)
        for i, target_h in outgoing {
            if i > 0 {
                io.write_string(writer, ", ")
            }
            io.write_string(writer, fmt.tprintf("%d", target_h.idx))
        }
        io.write_string(writer, "],\n")
    }
    
    io.write_string(writer, fmt.tprintf("      \"tv\": {\"strength\": %.6f, \"confidence\": %.6f},\n",
        atom.tv_get_strength(a.truth_value),
        atom.tv_get_confidence(a.truth_value)))
    
    io.write_string(writer, fmt.tprintf("      \"av\": {\"sti\": %d, \"lti\": %d, \"vlti\": %s}\n",
        a.attention_value.sti,
        a.attention_value.lti,
        a.attention_value.vlti ? "true" : "false"))
    
    io.write_string(writer, "    }")
}

// Escape string for JSON
escape_json_string :: proc(s: string) -> string {
    builder := strings.builder_make()
    
    for c in s {
        switch c {
            case '\\': strings.write_string(&builder, "\\\\")
            case '"':  strings.write_string(&builder, "\\\"")
            case '\n': strings.write_string(&builder, "\\n")
            case '\r': strings.write_string(&builder, "\\r")
            case '\t': strings.write_string(&builder, "\\t")
            case:      strings.write_byte(&builder, u8(c))
        }
    }
    
    return strings.to_string(builder)
}

// =============================================================================
// BINARY FORMAT (for performance)
// =============================================================================

// Binary format header
BINARY_MAGIC :: [4]u8{'O', 'C', 'O', 'G'}
BINARY_VERSION :: u32(1)

// Save AtomSpace in binary format
save_binary :: proc(as: ^atomspace.AtomSpace, filepath: string) -> bool {
    handle, err := os.open(filepath, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
    if err != nil {
        return false
    }
    defer os.close(handle)
    
    // Write header
    os.write(handle, BINARY_MAGIC[:])
    os.write_ptr(handle, &BINARY_VERSION, size_of(u32))
    
    // Write atom count
    count := u64(atomspace.atomspace_size(as))
    os.write_ptr(handle, &count, size_of(u64))
    
    // Write atoms
    it := atomspace.atomspace_iterator(as)
    for {
        a, h, ok := atomspace.atomspace_iterate(&it)
        if !ok {
            break
        }
        
        write_atom_binary(handle, a, h)
    }
    
    return true
}

// Write atom in binary format
write_atom_binary :: proc(handle: os.Handle, a: ^atom.Atom, h: atom.Handle) {
    // Handle
    os.write_ptr(handle, &h.idx, size_of(u32))
    os.write_ptr(handle, &h.gen, size_of(u32))
    
    // Type
    type_val := u16(a.atom_type)
    os.write_ptr(handle, &type_val, size_of(u16))
    
    // Truth value
    strength := atom.tv_get_strength(a.truth_value)
    confidence := atom.tv_get_confidence(a.truth_value)
    os.write_ptr(handle, &strength, size_of(f64))
    os.write_ptr(handle, &confidence, size_of(f64))
    
    // Attention value
    os.write_ptr(handle, &a.attention_value.sti, size_of(i16))
    os.write_ptr(handle, &a.attention_value.lti, size_of(i16))
    vlti_byte := u8(1) if a.attention_value.vlti else u8(0)
    os.write_ptr(handle, &vlti_byte, 1)
    
    // Node/Link specific data
    if atom.atom_is_node(a) {
        name := atom.atom_get_name(a)
        name_len := u32(len(name))
        os.write_ptr(handle, &name_len, size_of(u32))
        os.write(handle, transmute([]u8)name)
    } else if atom.atom_is_link(a) {
        outgoing := atom.atom_get_outgoing(a)
        arity := u32(len(outgoing))
        os.write_ptr(handle, &arity, size_of(u32))
        for target_h in outgoing {
            os.write_ptr(handle, &target_h.idx, size_of(u32))
            os.write_ptr(handle, &target_h.gen, size_of(u32))
        }
    }
}
