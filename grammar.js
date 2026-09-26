/**
 * @file Bend2 tree-sitter-parser
 * @author Thybault Alabarbe <thybault.alabarbe@gmail.com>
 * @license MIT
 */

/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

export default grammar({
  name: "bend2",

  rules: {
    // TODO: add the actual grammar rules
    source_file: $ => "hello"
  }
});
