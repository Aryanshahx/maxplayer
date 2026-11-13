import {test} from 'node:test';import assert from 'node:assert/strict';
import {validateThemeConfig} from './control-panel.mjs';
import {validateDraft} from './push-core.mjs';
const theme=()=>({schemaVersion:1,name:'Diwali',palette:{background:'#160D08',accent:'#FFC75A'},decoration:'diwali',headerLabel:'Happy Diwali'});
test('accepts a named theme and fills palette defaults',()=>{const t=validateThemeConfig(theme());assert.equal(t.name,'Diwali');assert.equal(t.palette.surface,'#101013');});
test('rejects executable code, unknown properties and malformed colours',()=>{assert.throws(()=>validateThemeConfig('eval(alert(1))'));assert.throws(()=>validateThemeConfig({...theme(),script:'bad'}));assert.throws(()=>validateThemeConfig({...theme(),palette:{accent:'url(javascript:bad)'}}));});
test('requires readable foreground contrast',()=>assert.throws(()=>validateThemeConfig({...theme(),palette:{background:'#FFFFFF',textPrimary:'#FFFFFF'}})));
test('does not accept arbitrary decoration code',()=>assert.throws(()=>validateThemeConfig({...theme(),decoration:'<script>bad</script>'})));
test('routes supported screens and requires a link for external',()=>{const n={title:'Test',message:'Body',target:'all',screen:'audio'};assert.equal(validateDraft(n).screen,'audio');assert.throws(()=>validateDraft({...n,screen:'execute'}));assert.throws(()=>validateDraft({...n,screen:'external'}));});
