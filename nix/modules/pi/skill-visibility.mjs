// Pi keeps the skill installed but omits it from the model's skill list.
export function manualSkill(markdown) {
  const frontmatter = /^(---\r?\n)([\s\S]*?)(^---[\t ]*\r?$)/m.exec(markdown);
  if (!frontmatter || frontmatter.index !== 0) {
    throw new Error('SKILL.md needs YAML frontmatter to mark it manual-only');
  }
  const [block, opening, fields, closing] = frontmatter;
  const newline = opening.endsWith('\r\n') ? '\r\n' : '\n';
  const field = /^disable-model-invocation:[^\r\n]*(?:\r?\n|$)/gm;
  return `${opening}disable-model-invocation: true${newline}${fields.replace(field, '')}${closing}${markdown.slice(block.length)}`;
}
