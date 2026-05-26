// OdinCog - OpenCog Implementation in Pure Odin
// Unified Rule Engine (URE)
//
// The URE provides a generic rule-based inference framework that supports:
// - Forward chaining (data-driven inference)
// - Backward chaining (goal-driven inference)
// - Rule selection and application
// - Inference control and termination

package odincog_ure

import "core:mem"
import "core:time"
import "core:fmt"
import "core:strings"
import "../../core/atom"
import "../../core/atomspace"
import "../../core/pattern"
import "../../core/types"
import "../pln"

// =============================================================================
// RULE STRUCTURE
// =============================================================================

// Rule represents an inference rule in the URE
Rule :: struct {
    // Rule identification
    name:        string,
    
    // Pattern to match (the premises)
    pattern:     ^pattern.Pattern,
    
    // Rewrite template (the conclusion)
    rewrite:     ^pattern.Pattern,
    
    // Rule metadata
    cost:        f64,           // Computational cost estimate
    weight:      f64,           // Selection weight (higher = more likely to be chosen)
    category:    RuleCategory,
    
    // Truth value formula to apply
    tv_formula:  TruthValueFormula,
    
    // Precondition check (optional)
    precondition: proc(^atomspace.AtomSpace, ^pattern.VariableBinding) -> bool,
    
    allocator:   mem.Allocator,
}

// Rule categories
RuleCategory :: enum {
    DEDUCTION,
    INDUCTION,
    ABDUCTION,
    MODUS_PONENS,
    AND_INTRODUCTION,
    AND_ELIMINATION,
    OR_INTRODUCTION,
    OR_ELIMINATION,
    NOT_INTRODUCTION,
    NOT_ELIMINATION,
    INHERITANCE,
    SIMILARITY,
    MEMBER,
    CUSTOM,
}

// Truth value formula types
TruthValueFormula :: enum {
    DEDUCTION,
    INDUCTION,
    ABDUCTION,
    MODUS_PONENS,
    REVISION,
    AND,
    OR,
    NOT,
    IDENTITY,  // Just copy the TV
    CUSTOM,
}

// Create a new rule
rule_create :: proc(
    name: string,
    allocator := context.allocator,
) -> ^Rule {
    r := new(Rule, allocator)
    r.name = strings.clone(name, allocator)
    r.pattern = pattern.pattern_create(allocator)
    r.rewrite = pattern.pattern_create(allocator)
    r.cost = 1.0
    r.weight = 1.0
    r.category = .CUSTOM
    r.tv_formula = .IDENTITY
    r.allocator = allocator
    return r
}

// Destroy a rule
rule_destroy :: proc(r: ^Rule) {
    if r == nil {
        return
    }
    delete(r.name, r.allocator)
    pattern.pattern_destroy(r.pattern)
    pattern.pattern_destroy(r.rewrite)
    free(r, r.allocator)
}

// =============================================================================
// RULE BASE
// =============================================================================

// RuleBase holds a collection of rules
RuleBase :: struct {
    rules:     [dynamic]^Rule,
    allocator: mem.Allocator,
}

// Create a rule base
rulebase_create :: proc(allocator := context.allocator) -> ^RuleBase {
    rb := new(RuleBase, allocator)
    rb.rules = make([dynamic]^Rule, allocator)
    rb.allocator = allocator
    return rb
}

// Destroy a rule base
rulebase_destroy :: proc(rb: ^RuleBase) {
    if rb == nil {
        return
    }
    for r in rb.rules {
        rule_destroy(r)
    }
    delete(rb.rules)
    free(rb, rb.allocator)
}

// Add a rule to the rule base
rulebase_add_rule :: proc(rb: ^RuleBase, r: ^Rule) {
    append(&rb.rules, r)
}

// Get all rules
rulebase_get_rules :: proc(rb: ^RuleBase) -> []^Rule {
    return rb.rules[:]
}

// Get rules by category
rulebase_get_by_category :: proc(rb: ^RuleBase, cat: RuleCategory, allocator := context.allocator) -> []^Rule {
    result := make([dynamic]^Rule, allocator)
    for r in rb.rules {
        if r.category == cat {
            append(&result, r)
        }
    }
    return result[:]
}

// =============================================================================
// INFERENCE RESULT
// =============================================================================

// InferenceResult holds the output of an inference step
InferenceResult :: struct {
    // New atom created (if any)
    atom_handle:   atom.Handle,
    
    // Rule that was applied
    rule:          ^Rule,
    
    // Variable bindings used
    bindings:      pattern.VariableBinding,
    
    // Computed truth value
    truth_value:   atom.TruthValue,
    
    // Inference metadata
    depth:         int,
    success:       bool,
}

// =============================================================================
// FORWARD CHAINER
// =============================================================================

// ForwardChainerConfig holds configuration for forward chaining
ForwardChainerConfig :: struct {
    max_steps:           int,           // Maximum inference steps
    max_time:            time.Duration, // Maximum time allowed
    min_confidence:      f64,           // Minimum confidence threshold
    max_results:         int,           // Maximum results to produce
    focus_set:           []atom.Handle, // Atoms to focus on (empty = all)
    attention_weighted:  bool,          // Use attention values for selection
}

DEFAULT_FC_CONFIG :: ForwardChainerConfig{
    max_steps = 100,
    max_time = time.Second * 30,
    min_confidence = 0.1,
    max_results = 10,
    focus_set = nil,
    attention_weighted = false,
}

// ForwardChainer performs data-driven inference
ForwardChainer :: struct {
    atomspace:    ^atomspace.AtomSpace,
    rulebase:     ^RuleBase,
    config:       ForwardChainerConfig,
    
    // Inference state
    results:      [dynamic]InferenceResult,
    steps:        int,
    start_time:   time.Time,
    
    // Working memory
    active_atoms: [dynamic]atom.Handle,
    
    allocator:    mem.Allocator,
}

// Create a forward chainer
fc_create :: proc(
    as: ^atomspace.AtomSpace,
    rb: ^RuleBase,
    config: ForwardChainerConfig = DEFAULT_FC_CONFIG,
    allocator := context.allocator,
) -> ^ForwardChainer {
    fc := new(ForwardChainer, allocator)
    fc.atomspace = as
    fc.rulebase = rb
    fc.config = config
    fc.results = make([dynamic]InferenceResult, allocator)
    fc.active_atoms = make([dynamic]atom.Handle, allocator)
    fc.allocator = allocator
    return fc
}

// Destroy forward chainer
fc_destroy :: proc(fc: ^ForwardChainer) {
    if fc == nil {
        return
    }
    for &r in fc.results {
        pattern.binding_destroy(&r.bindings)
    }
    delete(fc.results)
    delete(fc.active_atoms)
    free(fc, fc.allocator)
}

// Run forward chaining
fc_run :: proc(fc: ^ForwardChainer) -> []InferenceResult {
    fc.start_time = time.now()
    fc.steps = 0
    clear(&fc.results)
    
    // Initialize active atoms
    fc_init_active_atoms(fc)
    
    // Main inference loop
    for !fc_should_stop(fc) {
        // Select a rule to apply
        rule := fc_select_rule(fc)
        if rule == nil {
            break
        }
        
        // Try to apply the rule
        if fc_apply_rule(fc, rule) {
            fc.steps += 1
        }
        
        // Check termination conditions
        if len(fc.results) >= fc.config.max_results {
            break
        }
    }
    
    return fc.results[:]
}

// Initialize active atoms from focus set or all atoms
fc_init_active_atoms :: proc(fc: ^ForwardChainer) {
    clear(&fc.active_atoms)
    
    if len(fc.config.focus_set) > 0 {
        for h in fc.config.focus_set {
            append(&fc.active_atoms, h)
        }
    } else {
        // Use all atoms in atomspace
        it := atomspace.atomspace_iterator(fc.atomspace)
        for {
            _, h, ok := atomspace.atomspace_iterate(&it)
            if !ok {
                break
            }
            append(&fc.active_atoms, h)
        }
    }
}

// Check if forward chaining should stop
fc_should_stop :: proc(fc: ^ForwardChainer) -> bool {
    // Check step limit
    if fc.steps >= fc.config.max_steps {
        return true
    }
    
    // Check time limit
    elapsed := time.diff(fc.start_time, time.now())
    if elapsed >= fc.config.max_time {
        return true
    }
    
    // Check if we have any active atoms
    if len(fc.active_atoms) == 0 {
        return true
    }
    
    return false
}

// Select a rule to apply (simple random selection weighted by rule weight)
fc_select_rule :: proc(fc: ^ForwardChainer) -> ^Rule {
    rules := rulebase_get_rules(fc.rulebase)
    if len(rules) == 0 {
        return nil
    }
    
    // Simple round-robin for now
    idx := fc.steps % len(rules)
    return rules[idx]
}

// Try to apply a rule
fc_apply_rule :: proc(fc: ^ForwardChainer, rule: ^Rule) -> bool {
    // Find matches for the rule pattern
    matches := pattern.pattern_match_all(rule.pattern, fc.atomspace, 10, fc.allocator)
    defer {
        for &m in matches {
            pattern.binding_destroy(&m)
        }
    }
    
    if len(matches) == 0 {
        return false
    }
    
    applied := false
    
    for &binding in matches {
        // Check precondition
        if rule.precondition != nil && !rule.precondition(fc.atomspace, &binding) {
            continue
        }
        
        // Apply the rewrite
        result_handle := pattern.apply_bindings(rule.rewrite, &binding, fc.atomspace, rule.rewrite.root)
        if !atom.handle_is_valid(result_handle) {
            continue
        }
        
        // Compute truth value
        tv := fc_compute_tv(fc, rule, &binding)
        
        // Check confidence threshold
        if atom.tv_get_confidence(tv) < fc.config.min_confidence {
            continue
        }
        
        // Update atom's truth value
        if result_atom, ok := atomspace.atomspace_get(fc.atomspace, result_handle); ok {
            // Merge with existing TV using revision
            if !atom.tv_is_default(result_atom.truth_value) {
                tv = pln.tv_revision(result_atom.truth_value, tv)
            }
            result_atom.truth_value = tv
        }
        
        // Record result
        result := InferenceResult{
            atom_handle = result_handle,
            rule = rule,
            bindings = pattern.binding_clone(&binding),
            truth_value = tv,
            depth = 1,
            success = true,
        }
        append(&fc.results, result)
        
        // Add to active atoms for further inference
        append(&fc.active_atoms, result_handle)
        
        applied = true
    }
    
    return applied
}

// Compute truth value based on rule formula
fc_compute_tv :: proc(fc: ^ForwardChainer, rule: ^Rule, binding: ^pattern.VariableBinding) -> atom.TruthValue {
    // Get truth values of bound atoms
    tvs := make([dynamic]atom.TruthValue, fc.allocator)
    defer delete(tvs)
    
    for _, val_h in binding.bindings {
        if a, ok := atomspace.atomspace_get(fc.atomspace, val_h); ok {
            append(&tvs, a.truth_value)
        }
    }
    
    if len(tvs) == 0 {
        return atom.DEFAULT_TV
    }
    
    // Apply formula
    switch rule.tv_formula {
        case .AND:
            return pln.tv_and_n(tvs[:])
        case .OR:
            return pln.tv_or_n(tvs[:])
        case .NOT:
            if len(tvs) > 0 {
                return pln.tv_not(tvs[0])
            }
        case .DEDUCTION:
            if len(tvs) >= 2 {
                return pln.tv_deduction_simple(tvs[0], tvs[1])
            }
        case .MODUS_PONENS:
            if len(tvs) >= 2 {
                return pln.tv_modus_ponens(tvs[0], tvs[1])
            }
        case .REVISION:
            if len(tvs) >= 2 {
                return pln.tv_revision(tvs[0], tvs[1])
            }
        case .IDENTITY:
            if len(tvs) > 0 {
                return tvs[0]
            }
        case .INDUCTION, .ABDUCTION, .CUSTOM:
            // Would need more context
            if len(tvs) > 0 {
                return tvs[0]
            }
    }
    
    return atom.DEFAULT_TV
}

// =============================================================================
// BACKWARD CHAINER
// =============================================================================

// BackwardChainerConfig holds configuration for backward chaining
BackwardChainerConfig :: struct {
    max_depth:           int,           // Maximum proof tree depth
    max_time:            time.Duration, // Maximum time allowed
    min_confidence:      f64,           // Minimum confidence threshold
    max_solutions:       int,           // Maximum solutions to find
}

DEFAULT_BC_CONFIG :: BackwardChainerConfig{
    max_depth = 10,
    max_time = time.Second * 30,
    min_confidence = 0.1,
    max_solutions = 5,
}

// ProofNode represents a node in the proof tree
ProofNode :: struct {
    // Goal atom
    goal:          atom.Handle,
    
    // Rule used to derive this goal
    rule:          ^Rule,
    
    // Sub-goals (premises)
    children:      [dynamic]^ProofNode,
    
    // Bindings at this node
    bindings:      pattern.VariableBinding,
    
    // Status
    proved:        bool,
    failed:        bool,
    depth:         int,
    
    allocator:     mem.Allocator,
}

// Create proof node
proof_node_create :: proc(goal: atom.Handle, depth: int, allocator := context.allocator) -> ^ProofNode {
    pn := new(ProofNode, allocator)
    pn.goal = goal
    pn.children = make([dynamic]^ProofNode, allocator)
    pn.bindings = pattern.binding_create(allocator)
    pn.depth = depth
    pn.allocator = allocator
    return pn
}

// Destroy proof node (recursive)
proof_node_destroy :: proc(pn: ^ProofNode) {
    if pn == nil {
        return
    }
    for child in pn.children {
        proof_node_destroy(child)
    }
    delete(pn.children)
    pattern.binding_destroy(&pn.bindings)
    free(pn, pn.allocator)
}

// BackwardChainer performs goal-driven inference
BackwardChainer :: struct {
    atomspace:    ^atomspace.AtomSpace,
    rulebase:     ^RuleBase,
    config:       BackwardChainerConfig,
    
    // The goal to prove
    goal:         atom.Handle,
    
    // Proof tree root
    proof_root:   ^ProofNode,
    
    // Solutions found
    solutions:    [dynamic]pattern.VariableBinding,
    
    // Statistics
    nodes_expanded: int,
    start_time:   time.Time,
    
    allocator:    mem.Allocator,
}

// Create a backward chainer
bc_create :: proc(
    as: ^atomspace.AtomSpace,
    rb: ^RuleBase,
    goal: atom.Handle,
    config: BackwardChainerConfig = DEFAULT_BC_CONFIG,
    allocator := context.allocator,
) -> ^BackwardChainer {
    bc := new(BackwardChainer, allocator)
    bc.atomspace = as
    bc.rulebase = rb
    bc.config = config
    bc.goal = goal
    bc.solutions = make([dynamic]pattern.VariableBinding, allocator)
    bc.allocator = allocator
    return bc
}

// Destroy backward chainer
bc_destroy :: proc(bc: ^BackwardChainer) {
    if bc == nil {
        return
    }
    proof_node_destroy(bc.proof_root)
    for &s in bc.solutions {
        pattern.binding_destroy(&s)
    }
    delete(bc.solutions)
    free(bc, bc.allocator)
}

// Run backward chaining
bc_run :: proc(bc: ^BackwardChainer) -> []pattern.VariableBinding {
    bc.start_time = time.now()
    bc.nodes_expanded = 0
    clear(&bc.solutions)
    
    // Create root proof node
    bc.proof_root = proof_node_create(bc.goal, 0, bc.allocator)
    
    // Try to prove the goal
    bc_prove(bc, bc.proof_root)
    
    return bc.solutions[:]
}

// Try to prove a goal node
bc_prove :: proc(bc: ^BackwardChainer, node: ^ProofNode) -> bool {
    // Check termination conditions
    if bc_should_stop(bc, node) {
        return false
    }
    
    bc.nodes_expanded += 1
    
    // First, check if goal already exists in atomspace
    if atom.handle_is_valid(node.goal) {
        if a, ok := atomspace.atomspace_get(bc.atomspace, node.goal); ok {
            if atom.tv_is_true(a.truth_value) {
                node.proved = true
                return true
            }
        }
    }
    
    // Try to find rules that can derive this goal
    for rule in bc.rulebase.rules {
        // Check if rule's rewrite matches the goal pattern
        bindings, matches := bc_unify_goal_with_rewrite(bc, node.goal, rule)
        if !matches {
            continue
        }
        
        // Get the premises from the rule pattern
        premises := bc_extract_premises(bc, rule, &bindings)
        
        // Try to prove all premises
        all_proved := true
        children := make([dynamic]^ProofNode, bc.allocator)
        
        for premise in premises {
            child := proof_node_create(premise, node.depth + 1, bc.allocator)
            child.rule = rule
            append(&children, child)
            
            if !bc_prove(bc, child) {
                all_proved = false
                break
            }
        }
        
        if all_proved {
            node.children = children
            node.rule = rule
            node.bindings = bindings
            node.proved = true
            
            // Record solution
            append(&bc.solutions, pattern.binding_clone(&bindings))
            
            return true
        } else {
            // Clean up failed attempt
            for child in children {
                proof_node_destroy(child)
            }
            delete(children)
            pattern.binding_destroy(&bindings)
        }
    }
    
    node.failed = true
    return false
}

// Check if backward chaining should stop
bc_should_stop :: proc(bc: ^BackwardChainer, node: ^ProofNode) -> bool {
    // Check depth limit
    if node.depth >= bc.config.max_depth {
        return true
    }
    
    // Check time limit
    elapsed := time.diff(bc.start_time, time.now())
    if elapsed >= bc.config.max_time {
        return true
    }
    
    // Check solutions limit
    if len(bc.solutions) >= bc.config.max_solutions {
        return true
    }
    
    return false
}

// Try to unify goal with rule rewrite template
bc_unify_goal_with_rewrite :: proc(
    bc: ^BackwardChainer,
    goal: atom.Handle,
    rule: ^Rule,
) -> (pattern.VariableBinding, bool) {
    // Get the rewrite pattern root
    rewrite_root := rule.rewrite.root
    if !atom.handle_is_valid(rewrite_root) {
        return pattern.VariableBinding{}, false
    }
    
    // Create a binding and try to match
    binding := pattern.binding_create(bc.allocator)
    
    // For simplicity, check if types are compatible
    goal_atom, ok1 := atomspace.atomspace_get(bc.atomspace, goal)
    rewrite_atom, ok2 := pattern.pattern_get_atom(rule.rewrite, rewrite_root)
    
    if !ok1 || !ok2 {
        pattern.binding_destroy(&binding)
        return pattern.VariableBinding{}, false
    }
    
    // If rewrite root is a variable, it can match any goal
    if pattern.pattern_is_variable(rule.rewrite, rewrite_root) {
        pattern.binding_set(&binding, rewrite_root, goal)
        return binding, true
    }
    
    // Otherwise, types must match
    if goal_atom.atom_type != rewrite_atom.atom_type {
        pattern.binding_destroy(&binding)
        return pattern.VariableBinding{}, false
    }
    
    return binding, true
}

// Extract premises from rule pattern given bindings
bc_extract_premises :: proc(
    bc: ^BackwardChainer,
    rule: ^Rule,
    bindings: ^pattern.VariableBinding,
) -> []atom.Handle {
    result := make([dynamic]atom.Handle, bc.allocator)
    
    // The pattern root contains the premises
    // For now, just return variables that need to be proved
    for var_h in rule.pattern.variables {
        if !pattern.binding_is_bound(bindings, var_h) {
            // This variable needs a value - treat it as a premise
            // In a real implementation, we'd extract actual premise patterns
            append(&result, var_h)
        }
    }
    
    return result[:]
}

// =============================================================================
// BUILT-IN RULES
// =============================================================================

// Create deduction rule: (A->B, B->C) => A->C
create_deduction_rule :: proc(allocator := context.allocator) -> ^Rule {
    r := rule_create("deduction", allocator)
    r.category = .DEDUCTION
    r.tv_formula = .DEDUCTION
    r.weight = 1.0
    r.cost = 1.0
    
    // Pattern: (InheritanceLink $A $B) and (InheritanceLink $B $C)
    var_a := pattern.pattern_add_variable(r.pattern, "A", .CONCEPT_NODE)
    var_b := pattern.pattern_add_variable(r.pattern, "B", .CONCEPT_NODE)
    var_c := pattern.pattern_add_variable(r.pattern, "C", .CONCEPT_NODE)
    
    link_ab := pattern.pattern_add_link(r.pattern, .INHERITANCE_LINK, {var_a, var_b})
    link_bc := pattern.pattern_add_link(r.pattern, .INHERITANCE_LINK, {var_b, var_c})
    
    // Multi-clause pattern
    pattern.pattern_add_clause(r.pattern, link_ab)
    pattern.pattern_add_clause(r.pattern, link_bc)
    pattern.pattern_set_root(r.pattern, link_ab)
    
    // Rewrite: (InheritanceLink $A $C)
    rw_a := pattern.pattern_add_variable(r.rewrite, "A")
    rw_c := pattern.pattern_add_variable(r.rewrite, "C")
    link_ac := pattern.pattern_add_link(r.rewrite, .INHERITANCE_LINK, {rw_a, rw_c})
    pattern.pattern_set_root(r.rewrite, link_ac)
    
    return r
}

// Create modus ponens rule: (A, A->B) => B
create_modus_ponens_rule :: proc(allocator := context.allocator) -> ^Rule {
    r := rule_create("modus-ponens", allocator)
    r.category = .MODUS_PONENS
    r.tv_formula = .MODUS_PONENS
    r.weight = 1.0
    r.cost = 0.5
    
    // Pattern: $A and (ImplicationLink $A $B)
    var_a := pattern.pattern_add_variable(r.pattern, "A")
    var_b := pattern.pattern_add_variable(r.pattern, "B")
    
    impl := pattern.pattern_add_link(r.pattern, .IMPLICATION_LINK, {var_a, var_b})
    pattern.pattern_add_clause(r.pattern, var_a)
    pattern.pattern_add_clause(r.pattern, impl)
    pattern.pattern_set_root(r.pattern, impl)
    
    // Rewrite: $B
    rw_b := pattern.pattern_add_variable(r.rewrite, "B")
    pattern.pattern_set_root(r.rewrite, rw_b)
    
    return r
}

// Create and-introduction rule: (A, B) => (AndLink A B)
create_and_introduction_rule :: proc(allocator := context.allocator) -> ^Rule {
    r := rule_create("and-introduction", allocator)
    r.category = .AND_INTRODUCTION
    r.tv_formula = .AND
    r.weight = 0.5
    r.cost = 0.2
    
    // Pattern: $A and $B
    var_a := pattern.pattern_add_variable(r.pattern, "A")
    var_b := pattern.pattern_add_variable(r.pattern, "B")
    pattern.pattern_add_clause(r.pattern, var_a)
    pattern.pattern_add_clause(r.pattern, var_b)
    pattern.pattern_set_root(r.pattern, var_a)
    
    // Rewrite: (AndLink $A $B)
    rw_a := pattern.pattern_add_variable(r.rewrite, "A")
    rw_b := pattern.pattern_add_variable(r.rewrite, "B")
    and_link := pattern.pattern_add_link(r.rewrite, .AND_LINK, {rw_a, rw_b})
    pattern.pattern_set_root(r.rewrite, and_link)
    
    return r
}

// Create default rule base with common PLN rules
create_default_rulebase :: proc(allocator := context.allocator) -> ^RuleBase {
    rb := rulebase_create(allocator)
    
    rulebase_add_rule(rb, create_deduction_rule(allocator))
    rulebase_add_rule(rb, create_modus_ponens_rule(allocator))
    rulebase_add_rule(rb, create_and_introduction_rule(allocator))
    
    return rb
}
