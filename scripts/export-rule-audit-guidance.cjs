#!/usr/bin/env node
// Generated AI reference; maintain the React guidance, never edit the JSON by hand.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const Module = require('node:module');
const esbuild = require('esbuild');
const { parseFragment } = require('parse5');

const root = path.resolve(__dirname, '..');
const target = path.join(root, 'config/claims/rule_improvement_guidance.json');
const sha = (value) => crypto.createHash('sha256').update(value).digest('hex');
const entry = `
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { ChakraProvider } from '@chakra-ui/react';
import { improvementSteps } from './app/frontend/components/domains/rule-improvement-report/improvement-steps';
import { buildImprovementActions } from './app/frontend/components/domains/rule-improvement-report/action-signals';
import { RuleImprovementStepHelp } from './app/frontend/components/domains/rule-improvement-report/improvement-guide-help';
export function reference(engine) {
  // Values are placeholders for rendering help, not reported evidence. No counts/values are exported.
  const rule = {source_engine: engine, check_count: 1,
    candidate_false_positive_count: 0, candidate_false_negative_count: 0,
    multi_round_issue_count: 0, no_action_count: 0, corrected_documentation_count: 0,
    contractor_action: 'Read the selected rule record for its actual Pre-check Contractor Action.'};
  const breakdowns = {complaint_types: [], closure_types: [], admin_requests: [], contractor_responses: []};
  const actions = buildImprovementActions(rule as any, breakdowns as any);
  const steps = improvementSteps(engine === 'code');
  return {
    process_steps: steps,
    improvement_options: actions.map(({id,title,purpose,investigation,success,primarySignals}) => ({
      id,title,purpose,investigation,success,
      signal_guidance: primarySignals.map(({id,label,detail,interpretation}) => ({id,label,description: detail,what_to_investigate: interpretation}))
    })),
    detailed_help: steps.map(step => ({step:step.number,html: renderToStaticMarkup(
      <ChakraProvider><RuleImprovementStepHelp step={step.number} isCodeRule={engine === 'code'} rule={rule as any} actions={actions} /></ChakraProvider>
    )}))
  };
}
`;

const result = esbuild.buildSync({
  stdin: { contents: entry, resolveDir: root, loader: 'tsx' },
  bundle: true,
  platform: 'node',
  format: 'cjs',
  packages: 'external',
  write: false,
  metafile: true,
  logLevel: 'silent',
});
const compiled = new Module(path.join(root, 'scripts/.rule-audit-guidance-export.cjs'), module);
compiled.filename = path.join(root, 'scripts/.rule-audit-guidance-export.cjs');
compiled.paths = module.paths;
compiled._compile(result.outputFiles[0].text, compiled.filename);

function textFromHtml(html) {
  const blocks = new Set(['p', 'div', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'br']);
  function visit(node) {
    if (['style', 'script', 'svg'].includes(node.tagName)) return '';
    if (node.nodeName === '#text') return node.value;
    const inside = (node.childNodes || []).map(visit).join('');
    return blocks.has(node.tagName) ? '\n' + (node.tagName === 'li' ? '- ' : '') + inside + '\n' : inside;
  }
  return visit(parseFragment(html))
    .replace(/[ \t]+/g, ' ')
    .replace(/ *\n */g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

const sources = {};
for (const source of [...Object.keys(result.metafile.inputs), path.relative(root, __filename)].sort()) {
  if (source === '<stdin>') continue;
  const absolute = path.resolve(root, source);
  if (!absolute.startsWith(root + path.sep)) throw new Error('Unexpected guidance source outside repository.');
  sources[path.relative(root, absolute).split(path.sep).join('/')] = sha(
    fs.readFileSync(absolute, 'utf8').replace(/\r\n/g, '\n'),
  );
}
const engines = {};
for (const engine of ['genai', 'code']) {
  const reference = compiled.exports.reference(engine);
  reference.detailed_help = reference.detailed_help
    .map(({ step, html }) => ({ step, text: textFromHtml(html) }))
    .filter((item) => item.text);
  engines[engine] = reference;
}
const artifact = { schema_version: 1, generated_by: 'node scripts/export-rule-audit-guidance.cjs', sources, engines };
const content = JSON.stringify(artifact, null, 2) + '\n';
if (process.argv.includes('--check')) {
  if (!fs.existsSync(target) || fs.readFileSync(target, 'utf8').replace(/\r\n/g, '\n') !== content) {
    console.error('Rule audit guidance is stale. Run npm run rule-audit:guidance.');
    process.exitCode = 1;
  } else console.log('Rule audit guidance matches the maintained React source.');
} else {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, content);
  console.log(
    'Exported rule audit guidance: ' +
      Buffer.byteLength(content) +
      ' bytes; ' +
      Object.keys(sources).length +
      ' source digests.',
  );
}
