// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Code Reflection
//
// This module implements code introspection capabilities, allowing
// the agent to parse and analyze OdinCog source files and represent
// them as atoms in the AtomSpace.

package odincog_code_reflect

import "core:mem"
import "core:os"
import "core:strings"
import "core:fmt"
import "core:unicode/utf8"
import "../types"
import "../../core/atom"
import "../../core/atomspace"
import coreTypes "../../core/types"

// =============================================================================
// CODE MIRROR
// =============================================================================

// CodeMirror maintains an AtomSpace reflection of the codebase
CodeMirror :: struct {
    // AtomSpace containing code representation
    atomspace:          ^atomspace.AtomSpace,
    
    // Source root directory
    source_root:        string,
    
    // Parsed files
    parsed_files:       map[string]^FileRecord,
    
    // Symbol index
    symbol_index:       map[string]atom.Handle,
    
    // Call graph
    call_graph:         map[atom.Handle][dynamic]atom.Handle,
    
    // Statistics
    stats:              MirrorStats,
    
    allocator:          mem.Allocator,
}

// FileRecord holds parsed information about a source file
FileRecord :: struct {
    path:               string,
    module_name:        string,
    handle:             atom.Handle,
    
    // Parsed entities
    procedures:         [dynamic]^ProcedureRecord,
    types:              [dynamic]^TypeRecord,
    imports:            [dynamic]string,
    
    // Raw content
    content:            string,
    lines:              []string,
    
    // Modification tracking
    last_modified:      i64,
    checksum:           u64,
}

// ProcedureRecord holds parsed procedure information
ProcedureRecord :: struct {
    name:               string,
    handle:             atom.Handle,
    info:               types.ProcedureInfo,
    
    // Body analysis
    calls:              [dynamic]string,      // Procedures called
    reads:              [dynamic]string,      // Variables read
    writes:             [dynamic]string,      // Variables written
    
    // AST markers
    start_line:         int,
    end_line:           int,
}

// TypeRecord holds parsed type information
TypeRecord :: struct {
    name:               string,
    handle:             atom.Handle,
    info:               types.TypeInfo,
    
    start_line:         int,
    end_line:           int,
}

// MirrorStats tracks code mirror statistics
MirrorStats :: struct {
    files_parsed:       int,
    total_procedures:   int,
    total_types:        int,
    total_lines:        int,
    total_atoms:        int,
    call_edges:         int,
    data_edges:         int,
}

// =============================================================================
// CODE MIRROR LIFECYCLE
// =============================================================================

// Create a code mirror
code_mirror_create :: proc(
    as: ^atomspace.AtomSpace,
    source_root: string,
    allocator := context.allocator,
) -> ^CodeMirror {
    cm := new(CodeMirror, allocator)
    
    cm.atomspace = as
    cm.source_root = strings.clone(source_root, allocator)
    cm.parsed_files = make(map[string]^FileRecord, allocator)
    cm.symbol_index = make(map[string]atom.Handle, allocator)
    cm.call_graph = make(map[atom.Handle][dynamic]atom.Handle, allocator)
    cm.allocator = allocator
    
    return cm
}

// Destroy a code mirror
code_mirror_destroy :: proc(cm: ^CodeMirror) {
    if cm == nil {
        return
    }
    
    for path, record in cm.parsed_files {
        file_record_destroy(record, cm.allocator)
    }
    delete(cm.parsed_files)
    delete(cm.symbol_index)
    
    for _, calls in cm.call_graph {
        delete(calls)
    }
    delete(cm.call_graph)
    
    delete(cm.source_root, cm.allocator)
    free(cm, cm.allocator)
}

// Destroy a file record
file_record_destroy :: proc(record: ^FileRecord, allocator: mem.Allocator) {
    if record == nil {
        return
    }
    
    for proc_rec in record.procedures {
        delete(proc_rec.calls)
        delete(proc_rec.reads)
        delete(proc_rec.writes)
        free(proc_rec, allocator)
    }
    delete(record.procedures)
    
    for type_rec in record.types {
        free(type_rec, allocator)
    }
    delete(record.types)
    
    delete(record.imports)
    delete(record.lines, allocator)
    delete(record.content, allocator)
    
    free(record, allocator)
}

// =============================================================================
// PARSING
// =============================================================================

// Parse a source file and add to AtomSpace
code_mirror_parse_file :: proc(cm: ^CodeMirror, path: string) -> bool {
    // Read file content
    content, ok := os.read_entire_file(path, cm.allocator)
    if !ok {
        return false
    }
    
    content_str := string(content)
    
    // Create file record
    record := new(FileRecord, cm.allocator)
    record.path = strings.clone(path, cm.allocator)
    record.content = content_str
    record.procedures = make([dynamic]^ProcedureRecord, cm.allocator)
    record.types = make([dynamic]^TypeRecord, cm.allocator)
    record.imports = make([dynamic]string, cm.allocator)
    
    // Split into lines
    record.lines = strings.split(content_str, "\n", cm.allocator)
    
    // Extract module name from path
    record.module_name = extract_module_name(path)
    
    // Create file node
    file_handle, _ := atomspace.add_node(
        cm.atomspace,
        coreTypes.AtomType(int(coreTypes.AtomType.USER_DEFINED_START) + int(types.CodeAtomType.SOURCE_FILE_NODE)),
        path,
    )
    record.handle = file_handle
    
    // Create module node
    module_handle, _ := atomspace.add_node(
        cm.atomspace,
        coreTypes.AtomType(int(coreTypes.AtomType.USER_DEFINED_START) + int(types.CodeAtomType.MODULE_NODE)),
        record.module_name,
    )
    
    // Link file to module
    atomspace.add_link(
        cm.atomspace,
        coreTypes.AtomType(int(coreTypes.AtomType.USER_DEFINED_START) + int(types.CodeAtomType.CONTAINS_LINK)),
        []atom.Handle{file_handle, module_handle},
    )
    
    // Parse content
    parse_odin_file(cm, record)
    
    // Store record
    cm.parsed_files[path] = record
    cm.stats.files_parsed += 1
    cm.stats.total_lines += len(record.lines)
    
    return true
}

// Parse Odin source file content
parse_odin_file :: proc(cm: ^CodeMirror, record: ^FileRecord) {
    lines := record.lines
    i := 0
    
    for i < len(lines) {
        line := strings.trim_space(lines[i])
        
        // Skip empty lines and comments
        if len(line) == 0 || strings.has_prefix(line, "//") {
            i += 1
            continue
        }
        
        // Parse package declaration
        if strings.has_prefix(line, "package ") {
            record.module_name = extract_package_name(line)
            i += 1
            continue
        }
        
        // Parse imports
        if strings.has_prefix(line, "import ") {
            import_path := extract_import_path(line)
            if len(import_path) > 0 {
                append(&record.imports, import_path)
            }
            i += 1
            continue
        }
        
        // Parse procedure declarations
        if is_procedure_declaration(line) {
            proc_rec := parse_procedure(cm, record, lines, i)
            if proc_rec != nil {
                append(&record.procedures, proc_rec)
                i = proc_rec.end_line + 1
                continue
            }
        }
        
        // Parse type declarations
        if is_type_declaration(line) {
            type_rec := parse_type_declaration(cm, record, lines, i)
            if type_rec != nil {
                append(&record.types, type_rec)
                i = type_rec.end_line + 1
                continue
            }
        }
        
        i += 1
    }
}

// =============================================================================
// PROCEDURE PARSING
// =============================================================================

// Check if line is a procedure declaration
is_procedure_declaration :: proc(line: string) -> bool {
    // Look for "name :: proc" pattern
    return strings.contains(line, ":: proc")
}

// Parse a procedure declaration
parse_procedure :: proc(
    cm: ^CodeMirror,
    file_record: ^FileRecord,
    lines: []string,
    start_line: int,
) -> ^ProcedureRecord {
    line := strings.trim_space(lines[start_line])
    
    // Extract procedure name
    name_end := strings.index(line, "::")
    if name_end < 0 {
        return nil
    }
    name := strings.trim_space(line[:name_end])
    
    proc_rec := new(ProcedureRecord, cm.allocator)
    proc_rec.name = strings.clone(name, cm.allocator)
    proc_rec.start_line = start_line
    proc_rec.calls = make([dynamic]string, cm.allocator)
    proc_rec.reads = make([dynamic]string, cm.allocator)
    proc_rec.writes = make([dynamic]string, cm.allocator)
    
    // Find procedure body bounds
    brace_count := 0
    in_body := false
    end_line := start_line
    
    for i := start_line; i < len(lines); i += 1 {
        l := lines[i]
        
        for c in l {
            if c == '{' {
                brace_count += 1
                in_body = true
            } else if c == '}' {
                brace_count -= 1
                if in_body && brace_count == 0 {
                    end_line = i
                    break
                }
            }
        }
        
        if in_body && brace_count == 0 {
            break
        }
    }
    
    proc_rec.end_line = end_line
    
    // Analyze procedure body
    for i := start_line; i <= end_line; i += 1 {
        analyze_procedure_line(proc_rec, lines[i])
    }
    
    // Create procedure atom
    proc_handle, _ := atomspace.add_node(
        cm.atomspace,
        coreTypes.AtomType(int(coreTypes.AtomType.USER_DEFINED_START) + int(types.CodeAtomType.PROCEDURE_NODE)),
        name,
    )
    proc_rec.handle = proc_handle
    
    // Create DefinesLink from module to procedure
    atomspace.add_link(
        cm.atomspace,
        coreTypes.AtomType(int(coreTypes.AtomType.USER_DEFINED_START) + int(types.CodeAtomType.DEFINES_LINK)),
        []atom.Handle{file_record.handle, proc_handle},
    )
    
    // Store in symbol index
    full_name := fmt.aprintf("%s.%s", file_record.module_name, name, allocator = cm.allocator)
    cm.symbol_index[full_name] = proc_handle
    
    cm.stats.total_procedures += 1
    
    return proc_rec
}

// Analyze a line within a procedure body
analyze_procedure_line :: proc(proc_rec: ^ProcedureRecord, line: string) {
    // Simple call detection: look for "name(" patterns
    trimmed := strings.trim_space(line)
    
    // Skip comments
    if strings.has_prefix(trimmed, "//") {
        return
    }
    
    // Find function calls
    for i := 0; i < len(trimmed); i += 1 {
        if trimmed[i] == '(' && i > 0 {
            // Walk backwards to find function name
            end := i
            start := end - 1
            
            for start > 0 && is_identifier_char(trimmed[start]) {
                start -= 1
            }
            if !is_identifier_char(trimmed[start]) {
                start += 1
            }
            
            if end > start {
                call_name := trimmed[start:end]
                if len(call_name) > 0 && !is_keyword(call_name) {
                    append(&proc_rec.calls, strings.clone(call_name))
                }
            }
        }
    }
}

// Check if character is valid in an identifier
is_identifier_char :: proc(c: u8) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'
}

// Check if string is a keyword
is_keyword :: proc(s: string) -> bool {
    keywords := [?]string{
        "if", "else", "for", "while", "switch", "case", "return",
        "proc", "struct", "enum", "union", "import", "package",
        "true", "false", "nil", "when", "defer", "or_else",
    }
    
    for kw in keywords {
        if s == kw {
            return true
        }
    }
    return false
}

// =============================================================================
// TYPE PARSING
// =============================================================================

// Check if line is a type declaration
is_type_declaration :: proc(line: string) -> bool {
    return strings.contains(line, ":: struct") ||
           strings.contains(line, ":: enum") ||
           strings.contains(line, ":: union")
}

// Parse a type declaration
parse_type_declaration :: proc(
    cm: ^CodeMirror,
    file_record: ^FileRecord,
    lines: []string,
    start_line: int,
) -> ^TypeRecord {
    line := strings.trim_space(lines[start_line])
    
    // Extract type name
    name_end := strings.index(line, "::")
    if name_end < 0 {
        return nil
    }
    name := strings.trim_space(line[:name_end])
    
    // Determine type kind
    kind := types.CodeAtomType.CODE_TYPE_NODE
    if strings.contains(line, "struct") {
        kind = .STRUCT_NODE
    } else if strings.contains(line, "enum") {
        kind = .ENUM_NODE
    } else if strings.contains(line, "union") {
        kind = .UNION_NODE
    }
    
    type_rec := new(TypeRecord, cm.allocator)
    type_rec.name = strings.clone(name, cm.allocator)
    type_rec.start_line = start_line
    type_rec.info.name = name
    type_rec.info.kind = kind
    
    // Find type body bounds
    brace_count := 0
    in_body := false
    end_line := start_line
    
    for i := start_line; i < len(lines); i += 1 {
        l := lines[i]
        
        for c in l {
            if c == '{' {
                brace_count += 1
                in_body = true
            } else if c == '}' {
                brace_count -= 1
                if in_body && brace_count == 0 {
                    end_line = i
                    break
                }
            }
        }
        
        if in_body && brace_count == 0 {
            break
        }
    }
    
    type_rec.end_line = end_line
    
    // Create type atom
    type_handle, _ := atomspace.add_node(
        cm.atomspace,
        coreTypes.AtomType(int(coreTypes.AtomType.USER_DEFINED_START) + int(kind)),
        name,
    )
    type_rec.handle = type_handle
    
    // Create DefinesLink
    atomspace.add_link(
        cm.atomspace,
        coreTypes.AtomType(int(coreTypes.AtomType.USER_DEFINED_START) + int(types.CodeAtomType.DEFINES_LINK)),
        []atom.Handle{file_record.handle, type_handle},
    )
    
    // Store in symbol index
    full_name := fmt.aprintf("%s.%s", file_record.module_name, name, allocator = cm.allocator)
    cm.symbol_index[full_name] = type_handle
    
    cm.stats.total_types += 1
    
    return type_rec
}

// =============================================================================
// CALL GRAPH CONSTRUCTION
// =============================================================================

// Build call graph from parsed procedures
code_mirror_build_call_graph :: proc(cm: ^CodeMirror) {
    // Clear existing graph
    for _, calls in cm.call_graph {
        clear(&calls)
    }
    
    cm.stats.call_edges = 0
    
    // For each procedure, resolve its calls
    for _, record in cm.parsed_files {
        for proc_rec in record.procedures {
            caller := proc_rec.handle
            
            if !(caller in cm.call_graph) {
                cm.call_graph[caller] = make([dynamic]atom.Handle, cm.allocator)
            }
            
            for call_name in proc_rec.calls {
                // Try to resolve the call
                if callee := resolve_symbol(cm, record.module_name, call_name); atom.handle_is_valid(callee) {
                    append(&cm.call_graph[caller], callee)
                    
                    // Create CallsLink in AtomSpace
                    atomspace.add_link(
                        cm.atomspace,
                        coreTypes.AtomType(int(coreTypes.AtomType.USER_DEFINED_START) + int(types.CodeAtomType.CALLS_LINK)),
                        []atom.Handle{caller, callee},
                    )
                    
                    cm.stats.call_edges += 1
                }
            }
        }
    }
}

// Resolve a symbol name to a handle
resolve_symbol :: proc(cm: ^CodeMirror, module: string, name: string) -> atom.Handle {
    // Try fully qualified name
    full_name := fmt.tprintf("%s.%s", module, name)
    if h, ok := cm.symbol_index[full_name]; ok {
        return h
    }
    
    // Try just the name
    if h, ok := cm.symbol_index[name]; ok {
        return h
    }
    
    return atom.INVALID_HANDLE
}

// =============================================================================
// QUERIES
// =============================================================================

// Get all procedures in a module
code_mirror_get_procedures :: proc(cm: ^CodeMirror, module: string) -> []atom.Handle {
    result := make([dynamic]atom.Handle, context.temp_allocator)
    
    for _, record in cm.parsed_files {
        if record.module_name == module {
            for proc_rec in record.procedures {
                append(&result, proc_rec.handle)
            }
        }
    }
    
    return result[:]
}

// Get callers of a procedure
code_mirror_get_callers :: proc(cm: ^CodeMirror, proc_handle: atom.Handle) -> []atom.Handle {
    result := make([dynamic]atom.Handle, context.temp_allocator)
    
    for caller, callees in cm.call_graph {
        for callee in callees {
            if atom.handle_equals(callee, proc_handle) {
                append(&result, caller)
                break
            }
        }
    }
    
    return result[:]
}

// Get callees of a procedure
code_mirror_get_callees :: proc(cm: ^CodeMirror, proc_handle: atom.Handle) -> []atom.Handle {
    if callees, ok := cm.call_graph[proc_handle]; ok {
        return callees[:]
    }
    return nil
}

// Get statistics
code_mirror_get_stats :: proc(cm: ^CodeMirror) -> MirrorStats {
    cm.stats.total_atoms = int(atomspace.atomspace_size(cm.atomspace))
    return cm.stats
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

// Extract module name from file path
extract_module_name :: proc(path: string) -> string {
    // Get filename without extension
    start := strings.last_index(path, "/") + 1
    end := strings.last_index(path, ".")
    if end < start {
        end = len(path)
    }
    return path[start:end]
}

// Extract package name from package declaration
extract_package_name :: proc(line: string) -> string {
    // "package name" -> "name"
    parts := strings.split(line, " ", context.temp_allocator)
    if len(parts) >= 2 {
        return strings.trim_space(parts[1])
    }
    return ""
}

// Extract import path from import declaration
extract_import_path :: proc(line: string) -> string {
    // "import \"path\"" -> "path"
    start := strings.index(line, "\"")
    end := strings.last_index(line, "\"")
    if start >= 0 && end > start {
        return line[start+1:end]
    }
    return ""
}

// =============================================================================
// INCREMENTAL UPDATES
// =============================================================================

// Check if a file needs reparsing
code_mirror_needs_update :: proc(cm: ^CodeMirror, path: string) -> bool {
    record, ok := cm.parsed_files[path]
    if !ok {
        return true
    }
    
    // Check modification time
    stat, stat_ok := os.stat(path)
    if !stat_ok {
        return false
    }
    
    return stat.modification_time._nsec > record.last_modified
}

// Update a single file
code_mirror_update_file :: proc(cm: ^CodeMirror, path: string) -> bool {
    // Remove old record
    if record, ok := cm.parsed_files[path]; ok {
        // Remove atoms associated with this file
        // (In a real implementation, we'd track and remove these)
        
        file_record_destroy(record, cm.allocator)
        delete_key(&cm.parsed_files, path)
        
        cm.stats.files_parsed -= 1
    }
    
    // Reparse
    return code_mirror_parse_file(cm, path)
}
