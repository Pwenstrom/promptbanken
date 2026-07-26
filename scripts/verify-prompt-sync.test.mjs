import { strict as assert } from 'node:assert';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

const root = process.cwd();

function readJson(path) {
  return JSON.parse(readFileSync(join(root, path), 'utf8'));
}

test('all public prompts are present in web and MCP metadata surfaces', () => {
  const publicPrompts = readJson('prompts.json').prompts;
  const webSkills = new Set(readJson('skills.json').skills.map((skill) => skill.id));
  const mcpSkills = new Set(readJson('mcp-server/skills.json').skills.map((skill) => skill.id));

  const missing = [];

  for (const prompt of publicPrompts) {
    if (!existsSync(join(root, prompt.file))) {
      missing.push(`${prompt.id}: missing web prompt file ${prompt.file}`);
    }

    const mcpFile = prompt.file.replace(/^prompts\//, 'mcp-server/prompts/');
    if (!existsSync(join(root, mcpFile))) {
      missing.push(`${prompt.id}: missing MCP prompt file ${mcpFile}`);
    }

    if (!webSkills.has(prompt.id)) {
      missing.push(`${prompt.id}: missing skills.json metadata`);
    }

    if (!mcpSkills.has(prompt.id)) {
      missing.push(`${prompt.id}: missing mcp-server/skills.json metadata`);
    }
  }

  assert.deepEqual(missing, []);
});

test('MCP prompt text matches public prompt text', () => {
  const publicPrompts = readJson('prompts.json').prompts;
  const mismatches = [];

  for (const prompt of publicPrompts) {
    const mcpFile = prompt.file.replace(/^prompts\//, 'mcp-server/prompts/');

    if (!existsSync(join(root, prompt.file)) || !existsSync(join(root, mcpFile))) {
      continue;
    }

    const webText = readFileSync(join(root, prompt.file), 'utf8');
    const mcpText = readFileSync(join(root, mcpFile), 'utf8');

    if (webText !== mcpText) {
      mismatches.push(`${prompt.id}: ${prompt.file} differs from ${mcpFile}`);
    }
  }

  assert.deepEqual(mismatches, []);
});

test('web and MCP skill metadata match for shared prompts', () => {
  const webSkills = readJson('skills.json').skills;
  const mcpSkillsById = new Map(readJson('mcp-server/skills.json').skills.map((skill) => [skill.id, skill]));
  const mismatches = [];

  for (const webSkill of webSkills) {
    const mcpSkill = mcpSkillsById.get(webSkill.id);

    if (!mcpSkill) {
      continue;
    }

    if (JSON.stringify(webSkill) !== JSON.stringify(mcpSkill)) {
      mismatches.push(`${webSkill.id}: skills.json differs from mcp-server/skills.json`);
    }
  }

  assert.deepEqual(mismatches, []);
});
