package tree_sitter_bend2_test

import (
	"testing"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_bend2 "github.com/soulthym/tree-sitter-bend2/bindings/go"
)

func TestCanLoadGrammar(t *testing.T) {
	language := tree_sitter.NewLanguage(tree_sitter_bend2.Language())
	if language == nil {
		t.Errorf("Error loading Bend2 grammar")
	}
}
