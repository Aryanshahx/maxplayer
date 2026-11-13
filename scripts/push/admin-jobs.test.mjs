import {test} from 'node:test';import assert from 'node:assert/strict';
import {RESET_COLLECTIONS,validReset} from './admin-jobs.mjs';
import {validate,messageData} from './core.mjs';
test('reset collection allowlist never includes accounts, tokens, themes or notices',()=>assert.deepEqual(RESET_COLLECTIONS,['stats','reports']));
test('reset needs exact action, confirmation and actor',()=>{assert.equal(validReset({action:'resetAnalytics',confirmation:'RESET ANALYTICS',actor:'uid123'}),true);for(const v of [{action:'resetAll',confirmation:'RESET ANALYTICS',actor:'uid123'},{action:'resetAnalytics',confirmation:'reset',actor:'uid123'},{action:'resetAnalytics',confirmation:'RESET ANALYTICS',actor:'../admins'}])assert.equal(validReset(v),false);});
test('sender validates and forwards screen without executing it',()=>{const n={title:'Update',message:'Test',target:'all',screen:'private',createdAt:{toMillis:()=>1}};validate('id',n);assert.equal(messageData('id',n).screen,'private');assert.throws(()=>validate('id',{...n,screen:'unknown'}));});
