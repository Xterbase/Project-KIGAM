// web/assets/drop.js — 파일 끌어다 놓기 영역(#drop). index.php와 dashboard.php가 함께 쓴다.
// 파일을 고르거나 놓는 즉시 #upForm을 보낸다(처리는 index.php).
'use strict';
{
  const drop = document.getElementById('drop'), input = drop.querySelector('input'), form = document.getElementById('upForm');
  input.onchange = () => { if (input.files.length) { drop.querySelector('b').textContent = input.files[0].name + ' 올리는 중…'; form.submit(); } };
  drop.addEventListener('dragover', e => { e.preventDefault(); drop.classList.add('over'); });
  drop.addEventListener('dragleave', () => drop.classList.remove('over'));
  drop.addEventListener('drop', e => { e.preventDefault(); drop.classList.remove('over'); input.files = e.dataTransfer.files; input.onchange(); });
}
