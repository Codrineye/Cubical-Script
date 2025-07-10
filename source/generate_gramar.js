import { readFile, writeFileSync } from 'fs';
const components = JSON.parse(readFile('syntax.jsonc', 'utf-8'));
const grammar = JSON.parse(readFile('base.tmLanguage.json', 'utf-8'));

grammar.repository.impulses = {
  patterns: [{
    name: "keyword.control.impulse.cubical-script",
    match: `\\b(${components.impulses.join('|')})\\b`
  }]
};

grammar.repository.conditions = {
  patterns: [{
    name: "keyword.control.condition.cubical-script",
    match: `\\b(${components.conditions.join('|')})\\b`
  }]
};

grammar.repository.actions = {
  patterns: [{
    name: "keyword.control.action.cubical-script",
    match: `\\b(${components.actions.join('|')})\\b`
  }]
};

fs.writeFileSync('syntaxes/tpt2.tmLanguage.json', JSON.stringify(grammar, null, 2));
console.log("Grammar regenerated!");