# OdinCog

**OpenCog Implementation in Pure Odin Language**

OdinCog is a from-scratch implementation of the OpenCog cognitive architecture in the Odin programming language. It provides a high-performance, data-oriented implementation of the core OpenCog components for knowledge representation, reasoning, and learning.

## Features

### Core Foundation (Phase 1) ✅
- **Atom Type System**: Complete hierarchy of OpenCog atom types (ConceptNode, PredicateNode, InheritanceLink, etc.)
- **Atom Data Structures**: Handles, TruthValues, AttentionValues, Nodes, and Links
- **AtomSpace**: Central hypergraph knowledge container with O(1) lookup, type indexing, and incoming set tracking

### Pattern Matching (Phase 2) ✅
- **Variable Binding**: VariableNode and GlobNode support
- **Pattern Matcher**: Backtracking search with constraint propagation
- **Substitution**: Apply bindings to create grounded atoms

### Truth Value System (Phase 3) ✅
- **Truth Value Types**: Simple, Count, and Indefinite truth values
- **PLN Formulas**: Deduction, Induction, Abduction, Revision, AND/OR/NOT

### Unified Rule Engine (Phase 4) ✅
- **Rule Representation**: BindLink-compatible rules with patterns and rewrites
- **Forward Chainer**: Data-driven inference with configurable termination
- **Backward Chainer**: Goal-driven inference with proof tree generation

### ECAN Attention (Phase 6) ✅
- **Attention Values**: STI, LTI, VLTI management
- **Attentional Focus**: Importance-ordered atom access
- **ECAN Agents**: Importance spreading, diffusion, rent collection, forgetting

### Agent Framework (Phase 11) ✅
- **Mind Agents**: Generic agent interface with lifecycle management
- **Scheduler**: Priority-based agent scheduling with thread pool support

### Persistence (Phase 9) ✅
- **Atomese Format**: S-expression serialization compatible with OpenCog
- **JSON Format**: Interoperability format
- **Binary Format**: High-performance serialization

## Project Structure

```
odincog/
├── core/
│   ├── types/          # Atom type system and hierarchy
│   │   └── atom_types.odin
│   ├── atom/           # Atom structures (Handle, TruthValue, Node, Link)
│   │   └── atom.odin
│   ├── atomspace/      # AtomSpace container
│   │   └── atomspace.odin
│   └── pattern/        # Pattern matching engine
│       └── pattern.odin
├── reasoning/
│   ├── pln/            # Probabilistic Logic Networks
│   │   └── formulas.odin
│   └── ure/            # Unified Rule Engine
│       └── ure.odin
├── attention/
│   └── ecan/           # Economic Attention Allocation
│       └── ecan.odin
├── agents/
│   └── framework/      # Agent framework
│       └── agent.odin
├── persist/
│   └── file/           # File persistence
│       └── persist.odin
└── tests/              # Test suite
    └── tests.odin
```

## Usage

### Creating an AtomSpace

```odin
import "odincog/core/atomspace"
import "odincog/core/atom"
import "odincog/core/types"

main :: proc() {
    // Create AtomSpace
    as := atomspace.atomspace_create("main")
    defer atomspace.atomspace_destroy(as)
    
    // Add nodes
    dog, _ := atomspace.add_node(as, .CONCEPT_NODE, "dog", 
        atom.make_stv(0.9, 0.8))
    animal, _ := atomspace.add_node(as, .CONCEPT_NODE, "animal")
    
    // Add inheritance link
    atomspace.add_link(as, .INHERITANCE_LINK, {dog, animal},
        atom.make_stv(0.95, 0.9))
}
```

### Pattern Matching

```odin
import "odincog/core/pattern"

// Create pattern: (InheritanceLink $X (ConceptNode "animal"))
p := pattern.pattern_create()
defer pattern.pattern_destroy(p)

var_x := pattern.pattern_add_variable(p, "X", .CONCEPT_NODE)
animal_node := pattern.pattern_add_node(p, .CONCEPT_NODE, "animal")
link := pattern.pattern_add_link(p, .INHERITANCE_LINK, {var_x, animal_node})
pattern.pattern_set_root(p, link)

// Find all matches
matches := pattern.pattern_match_all(p, atomspace)
```

### PLN Inference

```odin
import "odincog/reasoning/pln"
import "odincog/reasoning/ure"

// Create rule base with default PLN rules
rb := ure.create_default_rulebase()
defer ure.rulebase_destroy(rb)

// Create forward chainer
fc := ure.fc_create(atomspace, rb)
defer ure.fc_destroy(fc)

// Run inference
results := ure.fc_run(fc)
```

### ECAN Attention

```odin
import "odincog/attention/ecan"

// Create ECAN manager
em := ecan.ecan_create(atomspace)
defer ecan.ecan_destroy(em)

// Run attention cycle
ecan.ecan_run_cycle(em)

// Check what's in focus
focus_atoms := ecan.af_get_atoms(em.focus)
```

### Persistence

```odin
import "odincog/persist/file"

// Save in Atomese format
file.save_atomese(atomspace, "knowledge.scm")

// Load from Atomese file
file.load_atomese(atomspace, "knowledge.scm")

// Save in JSON format
file.save_json(atomspace, "knowledge.json")
```

## Design Philosophy

OdinCog leverages Odin's strengths for a high-performance cognitive architecture:

1. **Data-Oriented Design**: SOA layouts for cache-efficient atom traversal
2. **Explicit Memory Management**: Custom allocators for atom pools
3. **No Hidden Control Flow**: Explicit error handling and control
4. **Compile-Time Safety**: Strong typing with discriminated unions

## Comparison with OpenCog C++

| Feature | OpenCog C++ | OdinCog |
|---------|-------------|---------|
| AtomSpace | ✅ | ✅ |
| Pattern Matching | ✅ | ✅ |
| PLN | ✅ | ✅ (Core formulas) |
| URE | ✅ | ✅ |
| ECAN | ✅ | ✅ |
| MOSES | ✅ | 🔜 Planned |
| NLP Pipeline | ✅ | 🔜 Planned |
| Distributed | ✅ | 🔜 Planned |

## Running Tests

```bash
cd odincog
odin test tests
```

## License

This implementation follows the same open-source principles as OpenCog.

## References

- [OpenCog Wiki](https://wiki.opencog.org/)
- [AtomSpace Documentation](https://wiki.opencog.org/w/AtomSpace)
- [PLN Book](https://wiki.opencog.org/w/PLN_Book)
- [Odin Language](https://odin-lang.org/)
