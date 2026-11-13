import {test} from 'node:test';import assert from 'node:assert/strict';
import {validateDraft} from './push-core.mjs';
test('routes supported screens and requires a link for external',()=>{const n={title:'Test',message:'Body',target:'all',screen:'audio'};assert.equal(validateDraft(n).screen,'audio');assert.throws(()=>validateDraft({...n,screen:'execute'}));assert.throws(()=>validateDraft({...n,screen:'external'}));});
