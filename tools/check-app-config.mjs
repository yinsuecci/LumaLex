import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const router = read('LumaLex/App/AppRouter.swift');
const profile = read('LumaLex/Views/Profile/ProfileView.swift');
assert.doesNotMatch(router + profile, /AssessmentView|showingAssessment|Retake Vocabulary Check/);
assert.match(router, /var body: some View\s*\{\s*mainTabs/);
assert.match(router, /VocabularyView\(\)/);
assert.match(profile, /KnownExpressionsView\(\)/);
assert.match(read('LumaLex/Info.plist'), /<key>UILaunchScreen<\/key>\s*<dict\s*\/>/);
const project = read('project.yml');
assert.match(project, /- Views\/Assessment\/\*\*/);
assert.match(project, /- Services\/Assessment\/\*\*/);
assert.match(project, /UILaunchScreen:\s*\{\}/);
console.log('Assessment removal and launch screen configuration checks passed.');
