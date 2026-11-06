import {mkdir,copyFile,writeFile} from 'node:fs/promises';
const supabaseUrl=process.env.SUPABASE_URL;
const publishableKey=process.env.SUPABASE_PUBLISHABLE_KEY;
if(!supabaseUrl||!/^https:\/\//.test(supabaseUrl)||!publishableKey)throw new Error('Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY');
if(publishableKey.startsWith('sb_secret_'))throw new Error('Secret keys must never be used in the browser');
if(publishableKey.split('.').length===3){try{const claims=JSON.parse(Buffer.from(publishableKey.split('.')[1],'base64url').toString());if(claims.role!=='anon')throw new Error('Only an anon JWT may be used as a legacy public key');}catch(e){throw new Error('Invalid public key: '+e.message)}}
await mkdir('dist',{recursive:true});
for(const file of ['index.html','styles.css','app.js'])await copyFile(file,'dist/'+file);
await writeFile('dist/config.js','window.KANBAN_CONFIG = Object.freeze('+JSON.stringify({supabaseUrl,publishableKey})+');\n');
console.log('Static build complete: dist');
