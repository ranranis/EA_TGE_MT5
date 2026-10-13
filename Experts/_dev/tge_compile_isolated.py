"""Invoke the same MetaEditor CLI as the compile skill, with UTF-8 path/log handling.
Only copies the EA's quoted includes/resources; never overwrites the live EX5.
"""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
root=Path.cwd()
source=root/'EA_T哥点位跟单.mq5'
version=re.search(r'#property version "([^"]+)"',source.read_text(encoding='utf-8-sig'))[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',default='_dev/compile/tge-v'+version)
args=parser.parse_args()
out=root/args.output
out.mkdir(parents=True,exist_ok=True)
seen=set()
def copy(p):
    p=p.resolve()
    if p in seen:return
    seen.add(p)
    dest=out/p.relative_to(root);dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(p,dest)
    if p.suffix.lower() not in ('.mq5','.mqh'):return
    text=p.read_text(encoding='utf-8-sig')
    for name in re.findall(r'^\s*#(?:include|resource)\s+"([^"]+)"',text,re.M):
        child=p.parent/name.replace('\\','/')
        copy(child)
copy(source)
log=out/'EA_Tge.compile.log'
if log.exists():log.unlink()
exe=Path('C:/Program Files/MetaTrader 5/MetaEditor64.exe')
startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
result=subprocess.run([str(exe),'/compile:'+str(out/source.name),'/log:'+str(log)],startupinfo=startup,timeout=60)
if not log.exists():raise SystemExit('MetaEditor did not produce a log')
raw=log.read_bytes();text=raw.decode('utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')
print(text)
summary=re.search(r'Result:\s*(\d+) errors?,\s*(\d+) warnings?',text)
print('SourceFile:',out/source.name,'MetaEditor:',exe,'ProcessCode:',result.returncode,'EX5:',(out/source.with_suffix('.ex5').name).exists())
if not summary or int(summary[1]):raise SystemExit(1)
