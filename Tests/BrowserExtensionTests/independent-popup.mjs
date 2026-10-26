import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const code=fs.readFileSync(new URL('../../Resources/ChromeExtension/popup.js',import.meta.url),'utf8');
let failures=0;
const scenarios={
  connected:{ok:true,appRunning:true,bridgeEnabled:true,protocolVersion:1,app:'Valora',appVersion:'1.0'},
  'app-not-running':{ok:true,appRunning:false,bridgeEnabled:false,protocolVersion:1,app:'Valora'},
  'download-off':{ok:true,appRunning:true,bridgeEnabled:false,protocolVersion:1,app:'Valora'},
  'host-missing':{hostMissing:true,ok:false,error:'not found'},
  'wrong-version':{ok:true,appRunning:true,bridgeEnabled:true,protocolVersion:999,app:'Valora'}
};
for (const [name,response] of Object.entries(scenarios)) {
  const elements={
    dot:{className:'dot'},
    status:{textContent:'正在检查…'},
    open:{hidden:true,disabled:false,textContent:'打开 Valora',listeners:{},addEventListener(t,f){this.listeners[t]=f;}},
    settings:{listeners:{},addEventListener(t,f){this.listeners[t]=f;}}
  };
  let launchCalls=0, tabCalls=0;
  const context={
    document:{getElementById:id=>elements[id]},
    window:{close(){}},
    chrome:{runtime:{sendNativeMessage(host,message,reply){ if(message.type==='launchApp') launchCalls++; reply(response); }},
      tabs:{create(){tabCalls++;}}},
    setTimeout, clearTimeout, console
  };
  vm.runInNewContext(code,context);
  await new Promise(r=>setTimeout(r,20));
  const shouldShow = name==='app-not-running'||name==='download-off'||name==='wrong-version';
  try {
    assert.equal(elements.open.hidden, !shouldShow, `${name}: open visibility`);
    if (name==='connected') assert.match(elements.status.textContent,/已连接/);
    if (name==='app-not-running') assert.match(elements.status.textContent,/未运行/);
    if (name==='download-off') assert.match(elements.status.textContent,/下载功能/);
    if (name==='host-missing') assert.match(elements.status.textContent,/尚未完成/);
    if (name==='wrong-version') assert.match(elements.status.textContent,/不匹配|未就绪/);
    if (shouldShow) {
      await elements.open.listeners.click();
      assert.equal(launchCalls,1,`${name}: explicit open`);
    } else {
      assert.equal(launchCalls,0,`${name}: no duplicate launch`);
    }
    console.log(JSON.stringify({scenario:name,passed:true,hidden:elements.open.hidden}));
  } catch (error) {
    failures++;
    console.log(JSON.stringify({scenario:name,passed:false,error:String(error),status:elements.status.textContent,hidden:elements.open.hidden}));
  }
}
process.exitCode=failures?1:0;
