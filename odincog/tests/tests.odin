// OdinCog - OpenCog Implementation in Pure Odin
// Test Suite
//
// This module contains tests for all OdinCog components.

package odincog_tests

import "core:testing"
import "core:fmt"
import "core:mem"

import "../core/types"
import "../core/atom"
import "../core/atomspace"
import "../core/pattern"
import "../reasoning/pln"
import "../reasoning/ure"
import "../attention/ecan"
import "../agents/framework"
import "../persist/file"

// =============================================================================
// TYPE SYSTEM TESTS
// =============================================================================

@(test)
test_type_hierarchy :: proc(t: ^testing.T) {
    // Test node types
    testing.expect(t, types.is_node(.CONCEPT_NODE), "ConceptNode should be a node")
    testing.expect(t, types.is_node(.PREDICATE_NODE), "PredicateNode should be a node")
    testing.expect(t, types.is_node(.VARIABLE_NODE), "VariableNode should be a node")
    
    // Test link types
    testing.expect(t, types.is_link(.INHERITANCE_LINK), "InheritanceLink should be a link")
    testing.expect(t, types.is_link(.AND_LINK), "AndLink should be a link")
    testing.expect(t, types.is_link(.EVALUATION_LINK), "EvaluationLink should be a link")
    
    // Test ordered vs unordered
    testing.expect(t, types.is_ordered_link(.INHERITANCE_LINK), "InheritanceLink should be ordered")
    testing.expect(t, types.is_unordered_link(.SET_LINK), "SetLink should be unordered")
    
    // Test subtype relationships
    testing.expect(t, types.is_subtype_of(.CONCEPT_NODE, .NODE), "ConceptNode should be subtype of Node")
    testing.expect(t, types.is_subtype_of(.INHERITANCE_LINK, .LINK), "InheritanceLink should be subtype of Link")
    testing.expect(t, types.is_subtype_of(.NODE, .ATOM), "Node should be subtype of Atom")
}

@(test)
test_type_predicates :: proc(t: ^testing.T) {
    testing.expect(t, types.is_variable(.VARIABLE_NODE), "VariableNode should be a variable")
    testing.expect(t, types.is_variable(.GLOB_NODE), "GlobNode should be a variable")
    testing.expect(t, !types.is_variable(.CONCEPT_NODE), "ConceptNode should not be a variable")
    
    testing.expect(t, types.is_logical_link(.AND_LINK), "AndLink should be logical")
    testing.expect(t, types.is_logical_link(.OR_LINK), "OrLink should be logical")
    testing.expect(t, types.is_logical_link(.NOT_LINK), "NotLink should be logical")
    
    testing.expect(t, types.is_scope_link(.LAMBDA_LINK), "LambdaLink should be a scope link")
    testing.expect(t, types.is_scope_link(.BIND_LINK), "BindLink should be a scope link")
}

// =============================================================================
// ATOM TESTS
// =============================================================================

@(test)
test_truth_value :: proc(t: ^testing.T) {
    // Test simple truth value
    tv := atom.make_stv(0.8, 0.9)
    testing.expect(t, atom.tv_get_strength(tv) == 0.8, "Strength should be 0.8")
    testing.expect(t, atom.tv_get_confidence(tv) == 0.9, "Confidence should be 0.9")
    
    // Test truth value predicates
    testing.expect(t, atom.tv_is_true(tv), "TV(0.8, 0.9) should be true")
    testing.expect(t, !atom.tv_is_default(tv), "TV(0.8, 0.9) should not be default")
    
    // Test default TV
    testing.expect(t, atom.tv_is_default(atom.DEFAULT_TV), "DEFAULT_TV should be default")
}

@(test)
test_attention_value :: proc(t: ^testing.T) {
    av := atom.make_av(100, 50, true)
    testing.expect(t, av.sti == 100, "STI should be 100")
    testing.expect(t, av.lti == 50, "LTI should be 50")
    testing.expect(t, av.vlti == true, "VLTI should be true")
    
    testing.expect(t, atom.av_in_focus(av), "AV with STI=100 should be in focus")
    testing.expect(t, !atom.av_in_focus(atom.DEFAULT_AV), "Default AV should not be in focus")
}

@(test)
test_node_creation :: proc(t: ^testing.T) {
    node := atom.make_node(.CONCEPT_NODE, "dog", atom.make_stv(0.9, 0.8))
    defer atom.atom_destroy(&node)
    
    testing.expect(t, atom.atom_is_node(&node), "Should be a node")
    testing.expect(t, !atom.atom_is_link(&node), "Should not be a link")
    testing.expect(t, atom.atom_get_name(&node) == "dog", "Name should be 'dog'")
    testing.expect(t, node.atom_type == .CONCEPT_NODE, "Type should be ConceptNode")
}

@(test)
test_link_creation :: proc(t: ^testing.T) {
    h1 := atom.Handle{idx = 1, gen = 1}
    h2 := atom.Handle{idx = 2, gen = 1}
    
    link := atom.make_link(.INHERITANCE_LINK, {h1, h2}, atom.make_stv(0.7, 0.6))
    defer atom.atom_destroy(&link)
    
    testing.expect(t, atom.atom_is_link(&link), "Should be a link")
    testing.expect(t, !atom.atom_is_node(&link), "Should not be a node")
    testing.expect(t, atom.atom_get_arity(&link) == 2, "Arity should be 2")
    
    out0, ok0 := atom.atom_get_outgoing_at(&link, 0)
    testing.expect(t, ok0 && atom.handle_equals(out0, h1), "First outgoing should be h1")
    
    out1, ok1 := atom.atom_get_outgoing_at(&link, 1)
    testing.expect(t, ok1 && atom.handle_equals(out1, h2), "Second outgoing should be h2")
}

// =============================================================================
// ATOMSPACE TESTS
// =============================================================================

@(test)
test_atomspace_basic :: proc(t: ^testing.T) {
    as := atomspace.atomspace_create("test")
    defer atomspace.atomspace_destroy(as)
    
    // Add a node
    h1, is_new1 := atomspace.add_node(as, .CONCEPT_NODE, "dog")
    testing.expect(t, atom.handle_is_valid(h1), "Handle should be valid")
    testing.expect(t, is_new1, "Should be a new atom")
    
    // Add same node again
    h2, is_new2 := atomspace.add_node(as, .CONCEPT_NODE, "dog")
    testing.expect(t, atom.handle_equals(h1, h2), "Should return same handle")
    testing.expect(t, !is_new2, "Should not be a new atom")
    
    // Check size
    testing.expect(t, atomspace.atomspace_size(as) == 1, "Size should be 1")
}

@(test)
test_atomspace_links :: proc(t: ^testing.T) {
    as := atomspace.atomspace_create("test")
    defer atomspace.atomspace_destroy(as)
    
    // Create nodes
    dog, _ := atomspace.add_node(as, .CONCEPT_NODE, "dog")
    animal, _ := atomspace.add_node(as, .CONCEPT_NODE, "animal")
    
    // Create inheritance link
    link, is_new := atomspace.add_link(as, .INHERITANCE_LINK, {dog, animal})
    testing.expect(t, atom.handle_is_valid(link), "Link handle should be valid")
    testing.expect(t, is_new, "Should be a new link")
    
    // Check link properties
    link_atom, found := atomspace.atomspace_get(as, link)
    testing.expect(t, found, "Link should be found")
    testing.expect(t, atom.atom_get_arity(link_atom) == 2, "Link arity should be 2")
    
    // Check incoming set
    incoming := atomspace.get_incoming(as, dog)
    testing.expect(t, len(incoming) == 1, "Dog should have 1 incoming link")
    testing.expect(t, atom.handle_equals(incoming[0], link), "Incoming should be the inheritance link")
}

@(test)
test_atomspace_type_index :: proc(t: ^testing.T) {
    as := atomspace.atomspace_create("test")
    defer atomspace.atomspace_destroy(as)
    
    // Add nodes of different types
    atomspace.add_node(as, .CONCEPT_NODE, "dog")
    atomspace.add_node(as, .CONCEPT_NODE, "cat")
    atomspace.add_node(as, .PREDICATE_NODE, "likes")
    
    // Query by type
    concepts := atomspace.get_atoms_by_type(as, .CONCEPT_NODE, false)
    testing.expect(t, len(concepts) == 2, "Should have 2 ConceptNodes")
    
    predicates := atomspace.get_atoms_by_type(as, .PREDICATE_NODE, false)
    testing.expect(t, len(predicates) == 1, "Should have 1 PredicateNode")
    
    nodes := atomspace.get_atoms_by_type(as, .NODE, true)
    testing.expect(t, len(nodes) == 3, "Should have 3 Nodes total")
}

// =============================================================================
// PATTERN MATCHING TESTS
// =============================================================================

@(test)
test_pattern_variable_binding :: proc(t: ^testing.T) {
    b := pattern.binding_create()
    defer pattern.binding_destroy(&b)
    
    h1 := atom.Handle{idx = 1, gen = 1}
    h2 := atom.Handle{idx = 2, gen = 1}
    var_h := atom.Handle{idx = 100, gen = 1}
    
    // Bind variable
    ok := pattern.binding_set(&b, var_h, h1)
    testing.expect(t, ok, "First binding should succeed")
    
    // Check binding
    val, found := pattern.binding_get(&b, var_h)
    testing.expect(t, found, "Variable should be bound")
    testing.expect(t, atom.handle_equals(val, h1), "Should be bound to h1")
    
    // Try to rebind to same value
    ok = pattern.binding_set(&b, var_h, h1)
    testing.expect(t, ok, "Rebinding to same value should succeed")
    
    // Try to rebind to different value
    ok = pattern.binding_set(&b, var_h, h2)
    testing.expect(t, !ok, "Rebinding to different value should fail")
}

@(test)
test_pattern_matching :: proc(t: ^testing.T) {
    as := atomspace.atomspace_create("test")
    defer atomspace.atomspace_destroy(as)
    
    // Create knowledge base
    dog, _ := atomspace.add_node(as, .CONCEPT_NODE, "dog")
    cat, _ := atomspace.add_node(as, .CONCEPT_NODE, "cat")
    animal, _ := atomspace.add_node(as, .CONCEPT_NODE, "animal")
    
    atomspace.add_link(as, .INHERITANCE_LINK, {dog, animal})
    atomspace.add_link(as, .INHERITANCE_LINK, {cat, animal})
    
    // Create pattern: (InheritanceLink $X (ConceptNode "animal"))
    p := pattern.pattern_create()
    defer pattern.pattern_destroy(p)
    
    var_x := pattern.pattern_add_variable(p, "X", .CONCEPT_NODE)
    animal_pattern := pattern.pattern_add_node(p, .CONCEPT_NODE, "animal")
    link_pattern := pattern.pattern_add_link(p, .INHERITANCE_LINK, {var_x, animal_pattern})
    pattern.pattern_set_root(p, link_pattern)
    
    // Find matches
    matches := pattern.pattern_match_all(p, as)
    defer {
        for &m in matches {
            pattern.binding_destroy(&m)
        }
    }
    
    testing.expect(t, len(matches) == 2, "Should find 2 matches (dog and cat)")
}

// =============================================================================
// TRUTH VALUE FORMULA TESTS
// =============================================================================

@(test)
test_tv_not :: proc(t: ^testing.T) {
    tv := atom.make_stv(0.8, 0.9)
    not_tv := pln.tv_not(tv)
    
    testing.expect(t, abs(atom.tv_get_strength(not_tv) - 0.2) < 0.001, "NOT(0.8) should be 0.2")
    testing.expect(t, atom.tv_get_confidence(not_tv) == 0.9, "Confidence should be preserved")
}

@(test)
test_tv_and :: proc(t: ^testing.T) {
    tv1 := atom.make_stv(0.8, 0.9)
    tv2 := atom.make_stv(0.6, 0.8)
    
    and_tv := pln.tv_and(tv1, tv2)
    expected_s := 0.8 * 0.6  // 0.48
    
    testing.expect(t, abs(atom.tv_get_strength(and_tv) - expected_s) < 0.001, "AND strength should be product")
    testing.expect(t, atom.tv_get_confidence(and_tv) == 0.8, "AND confidence should be minimum")
}

@(test)
test_tv_or :: proc(t: ^testing.T) {
    tv1 := atom.make_stv(0.8, 0.9)
    tv2 := atom.make_stv(0.6, 0.8)
    
    or_tv := pln.tv_or(tv1, tv2)
    expected_s := 0.8 + 0.6 - 0.8 * 0.6  // 0.92
    
    testing.expect(t, abs(atom.tv_get_strength(or_tv) - expected_s) < 0.001, "OR strength should follow formula")
    testing.expect(t, atom.tv_get_confidence(or_tv) == 0.8, "OR confidence should be minimum")
}

@(test)
test_tv_revision :: proc(t: ^testing.T) {
    tv1 := atom.make_stv(0.8, 0.5)
    tv2 := atom.make_stv(0.6, 0.5)
    
    rev_tv := pln.tv_revision(tv1, tv2)
    
    // Combined should have higher confidence
    testing.expect(t, atom.tv_get_confidence(rev_tv) > 0.5, "Revised confidence should be higher")
    // Strength should be average-ish
    s := atom.tv_get_strength(rev_tv)
    testing.expect(t, s >= 0.6 && s <= 0.8, "Revised strength should be between inputs")
}

// =============================================================================
// ECAN TESTS
// =============================================================================

@(test)
test_ecan_basic :: proc(t: ^testing.T) {
    as := atomspace.atomspace_create("test")
    defer atomspace.atomspace_destroy(as)
    
    // Add some atoms
    atomspace.add_node(as, .CONCEPT_NODE, "dog", atom.DEFAULT_TV, atom.make_av(50, 0))
    atomspace.add_node(as, .CONCEPT_NODE, "cat", atom.DEFAULT_TV, atom.make_av(150, 0))
    
    // Create ECAN manager
    em := ecan.ecan_create(as)
    defer ecan.ecan_destroy(em)
    
    // Update attentional focus
    ecan.af_update(em.focus)
    
    // Cat should be in focus (STI=150), dog should not (STI=50)
    focus_atoms := ecan.af_get_atoms(em.focus)
    testing.expect(t, len(focus_atoms) == 1, "Only cat should be in focus")
}

// =============================================================================
// AGENT FRAMEWORK TESTS
// =============================================================================

@(test)
test_agent_basic :: proc(t: ^testing.T) {
    as := atomspace.atomspace_create("test")
    defer atomspace.atomspace_destroy(as)
    
    run_count := 0
    
    agent := framework.agent_create(
        "test-agent",
        "A test agent",
        as,
        proc(a: ^framework.Agent) -> bool {
            // Can't access run_count here in Odin's closure model
            return true
        },
    )
    defer framework.agent_destroy(agent)
    
    testing.expect(t, agent.info.status == .IDLE, "Agent should start IDLE")
    testing.expect(t, agent.info.name == "test-agent", "Name should match")
    
    // Run agent
    result := framework.agent_run_once(agent)
    testing.expect(t, result, "Agent run should succeed")
    testing.expect(t, agent.info.total_runs == 1, "Total runs should be 1")
}

// =============================================================================
// HELPER
// =============================================================================

abs :: proc(x: f64) -> f64 {
    return x if x >= 0 else -x
}
