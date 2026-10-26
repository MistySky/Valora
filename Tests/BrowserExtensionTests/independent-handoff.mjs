import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const code=fs.readFileSync(new URL('../../Resources/ChromeExtension/background.js',import.meta.url),'utf8');
let failures=0;
const scenarios=[
  'accepted', 'unconfirmed-ok', 'cancel-failed', 'host-no-callback',
  'late-status', 'late-download', 'feature-off', 'host-missing'
];
for (const scenario of scenarios) {
  let listener, suggestions=0, cancelled=0, erased=0, downloadCalls=0;
  const event={addListener(){}};
  const statusResponse={ok:true,appRunning:true,bridgeEnabled:true,protocolVersion:1,app:'Valora'};
  const acceptedResponse={ok:true,accepted:true,protocolVersion:1,app:'Valora',
    appBundleIdentifier:'com.wangqing.valora'};
  const runtime={id:'fixture-extension',onInstalled:event,onStartup:event,onMessage:event,
    getURL:x=>x,
    sendNativeMessage(host,message,reply){
      if(message.type==='status') {
        if(scenario==='host-no-callback') return;
        if(scenario==='late-status') {
          setTimeout(()=>reply(statusResponse),30);
          return;
        }
        if(scenario==='feature-off') {
          reply({ok:true,appRunning:false,bridgeEnabled:false,protocolVersion:1,app:'Valora'});
          return;
        }
        if(scenario==='host-missing') {
          runtime.lastError={message:'Specified native messaging host not found.'};
          reply(undefined);
          delete runtime.lastError;
          return;
        }
        reply(statusResponse);
        return;
      }
      downloadCalls++;
      if(scenario==='unconfirmed-ok') {
        reply({ok:true,protocolVersion:1,app:'Valora'});
        return;
      }
      if(scenario==='late-download') {
        setTimeout(()=>reply(acceptedResponse),30);
        return;
      }
      reply(acceptedResponse);
    }};
  const chrome={runtime,notifications:{create(){}},
    contextMenus:{onClicked:event,removeAll(cb){cb();},create(){}},
    downloads:{onDeterminingFilename:{addListener(fn){listener=fn;}},
      cancel(id,cb){
        cancelled++;
        if(scenario==='cancel-failed') runtime.lastError={message:'cancel failed'};
        cb();
        delete runtime.lastError;
      },
      erase(){erased++;}}};
  vm.runInNewContext(code,{chrome,URL,console,Date,setTimeout,clearTimeout,
    globalThis:{__valoraNativeDeadlineMs:20}});
  listener({id:1,url:'https://example.invalid/fixture.bin',state:'in_progress',
    startTime:new Date().toISOString()},()=>suggestions++);
  await new Promise(resolve=>setTimeout(resolve,scenario.startsWith('late')||scenario==='host-no-callback'?70:25));
  const expected={
    accepted:{suggestions:1,cancelled:1,erased:1},
    'unconfirmed-ok':{suggestions:1,cancelled:0,erased:0},
    'cancel-failed':{suggestions:1,cancelled:1,erased:0},
    'host-no-callback':{suggestions:1,cancelled:0,erased:0},
    'late-status':{suggestions:1,cancelled:0,erased:0},
    'late-download':{suggestions:1,cancelled:0,erased:0},
    'feature-off':{suggestions:1,cancelled:0,erased:0},
    'host-missing':{suggestions:1,cancelled:0,erased:0}
  }[scenario];
  const actual={suggestions,cancelled,erased};
  try {
    assert.deepEqual(actual,expected);
    assert.equal(downloadCalls, scenario==='late-status'||scenario==='host-no-callback'||scenario==='feature-off'||scenario==='host-missing'?0:1);
    console.log(JSON.stringify({scenario,passed:true,actual,downloadCalls}));
  } catch {
    failures++;
    console.log(JSON.stringify({scenario,passed:false,expected,actual,downloadCalls}));
  }
}
process.exitCode=failures?1:0;
