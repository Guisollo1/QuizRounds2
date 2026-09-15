import fs from 'node:fs';
import path from 'node:path';
const root=process.cwd(),errors=[];
const read=r=>fs.readFileSync(path.join(root,r),'utf8');
const check=(cond,msg)=>{if(!cond)errors.push(msg);};
const adminHtml=read('admin.html');
const admin=read('assets/js/admin-v3.68-r89.js');
const display=read('assets/js/display-v3.68-r89.js');
const css=read('assets/css/admin-v3.68-r89.css');
check(adminHtml.includes('id="createExampleGameBtn"'),'botão Partida de exemplo ausente');
for(const token of ['EXAMPLE_GAME_QUESTIONS','Quanto é 12 × 10?','correctNumber:120','async function createExampleGame()','journeyGo(\'lobby\')'])check(admin.includes(token),`Partida de exemplo sem marcador: ${token}`);
check((admin.match(/prompt:'/g)||[]).length>=2,'menos de 2 perguntas de exemplo definidas');
check(css.includes('grid-template-columns:repeat(2,minmax(0,1fr))'),'grade da Central não acomoda os 4 botões em 2x2');
for(const token of ['scheduleCountdownRecovery','countdownRecoveryAttempts','preparing?900','remain<=0)scheduleCountdownRecovery()','phase===\'preparing\')refresh(true)'])check(display.includes(token),`recuperação da contagem ausente: ${token}`);
check(display.includes('POLL_CONNECTED=9000'),'poll conectado normal do telão deve continuar 9000 ms fora da contagem');
if(errors.length){console.error(`VALIDAÇÃO r89 EXEMPLO/CONTAGEM: REPROVADA (${errors.length})`);errors.forEach((e,i)=>console.error(`ERRO ${i+1}: ${e}`));process.exit(1);}
console.log('VALIDAÇÃO r89 EXEMPLO/CONTAGEM: APROVADA — 2 perguntas, lobby direto e recuperação da transição 3-2-1.');
